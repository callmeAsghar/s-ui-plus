package core

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"

	"github.com/gofrs/uuid/v5"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing/common/buf"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/common/network"
)

type ConnectionInfo struct {
	ID         string
	Conn       net.Conn
	PacketConn network.PacketConn
	Inbound    string
	Type       string // "tcp" or "udp"
	User       string
	SourceIP   string
}

type ConnTracker struct {
	access       sync.Mutex
	connections  map[string]*ConnectionInfo
	singleIPUser map[string]struct{}
	// user (sing-box client name) -> source IP -> connection IDs
	userIPConns map[string]map[string]map[string]struct{}
}

func NewConnTracker() *ConnTracker {
	return &ConnTracker{
		connections:  make(map[string]*ConnectionInfo),
		singleIPUser: make(map[string]struct{}),
		userIPConns:  make(map[string]map[string]map[string]struct{}),
	}
}

func (c *ConnTracker) SetSingleIpUsers(names []string) {
	c.access.Lock()
	defer c.access.Unlock()
	c.singleIPUser = make(map[string]struct{}, len(names))
	for _, n := range names {
		if n != "" {
			c.singleIPUser[n] = struct{}{}
		}
	}
}

func (c *ConnTracker) Reset() {
	c.access.Lock()
	defer c.access.Unlock()
	for _, connInfo := range c.connections {
		if connInfo.Conn != nil {
			_ = connInfo.Conn.Close()
		}
		if connInfo.PacketConn != nil {
			_ = connInfo.PacketConn.Close()
		}
	}
	c.connections = make(map[string]*ConnectionInfo)
	c.userIPConns = make(map[string]map[string]map[string]struct{})
}

func (c *ConnTracker) generateConnectionID() string {
	return uuid.Must(uuid.NewV4()).String()
}

func hostFromNetAddr(addr net.Addr) string {
	if addr == nil {
		return ""
	}
	s := addr.String()
	host, _, err := net.SplitHostPort(s)
	if err != nil {
		if ip := net.ParseIP(s); ip != nil {
			return ip.String()
		}
		return s
	}
	if h := net.ParseIP(host); h != nil {
		return h.String()
	}
	return host
}

func (c *ConnTracker) singleIPEnforced(user string) bool {
	if user == "" {
		return false
	}
	_, ok := c.singleIPUser[user]
	return ok
}

func (c *ConnTracker) collectEvictionsLocked(user, newIP string) []*ConnectionInfo {
	if newIP == "" || !c.singleIPEnforced(user) {
		return nil
	}
	byIP, ok := c.userIPConns[user]
	if !ok {
		return nil
	}
	var out []*ConnectionInfo
	for ip, ids := range byIP {
		if ip == newIP {
			continue
		}
		for id := range ids {
			if ci, exists := c.connections[id]; exists {
				out = append(out, ci)
			}
		}
	}
	return out
}

func (c *ConnTracker) unlinkConnLocked(connID string, ci *ConnectionInfo) {
	delete(c.connections, connID)
	if ci.User == "" || ci.SourceIP == "" {
		return
	}
	byIP, ok := c.userIPConns[ci.User]
	if !ok {
		return
	}
	set, ok := byIP[ci.SourceIP]
	if !ok {
		return
	}
	delete(set, connID)
	if len(set) == 0 {
		delete(byIP, ci.SourceIP)
	}
	if len(byIP) == 0 {
		delete(c.userIPConns, ci.User)
	}
}

func (c *ConnTracker) linkConnLocked(connID string, ci *ConnectionInfo) {
	if ci.User == "" || ci.SourceIP == "" || !c.singleIPEnforced(ci.User) {
		return
	}
	if c.userIPConns[ci.User] == nil {
		c.userIPConns[ci.User] = make(map[string]map[string]struct{})
	}
	if c.userIPConns[ci.User][ci.SourceIP] == nil {
		c.userIPConns[ci.User][ci.SourceIP] = make(map[string]struct{})
	}
	c.userIPConns[ci.User][ci.SourceIP][connID] = struct{}{}
}

func (c *ConnTracker) RoutedConnection(ctx context.Context, conn net.Conn, metadata adapter.InboundContext, matchedRule adapter.Rule, matchOutbound adapter.Outbound) net.Conn {
	connID := c.generateConnectionID()
	user := metadata.User
	srcIP := hostFromNetAddr(conn.RemoteAddr())

	var evict []*ConnectionInfo
	c.access.Lock()
	evict = c.collectEvictionsLocked(user, srcIP)
	for _, ci := range evict {
		c.unlinkConnLocked(ci.ID, ci)
	}
	connInfo := &ConnectionInfo{
		ID:       connID,
		Conn:     conn,
		Inbound:  metadata.Inbound,
		Type:     "tcp",
		User:     user,
		SourceIP: srcIP,
	}
	c.connections[connID] = connInfo
	c.linkConnLocked(connID, connInfo)
	c.access.Unlock()

	for _, ci := range evict {
		if ci.Conn != nil {
			_ = ci.Conn.Close()
		}
		if ci.PacketConn != nil {
			_ = ci.PacketConn.Close()
		}
	}

	return c.createWrappedConn(conn, connID)
}

func (c *ConnTracker) RoutedPacketConnection(ctx context.Context, conn network.PacketConn, metadata adapter.InboundContext, matchedRule adapter.Rule, matchOutbound adapter.Outbound) network.PacketConn {
	connID := c.generateConnectionID()
	user := metadata.User
	srcIP := ""
	type withRemote interface {
		RemoteAddr() net.Addr
	}
	if wr, ok := conn.(withRemote); ok {
		srcIP = hostFromNetAddr(wr.RemoteAddr())
	}

	var evict []*ConnectionInfo
	c.access.Lock()
	evict = c.collectEvictionsLocked(user, srcIP)
	for _, ci := range evict {
		c.unlinkConnLocked(ci.ID, ci)
	}
	connInfo := &ConnectionInfo{
		ID:         connID,
		PacketConn: conn,
		Inbound:    metadata.Inbound,
		Type:       "udp",
		User:       user,
		SourceIP:   srcIP,
	}
	c.connections[connID] = connInfo
	c.linkConnLocked(connID, connInfo)
	c.access.Unlock()

	for _, ci := range evict {
		if ci.Conn != nil {
			_ = ci.Conn.Close()
		}
		if ci.PacketConn != nil {
			_ = ci.PacketConn.Close()
		}
	}

	return c.createWrappedPacketConn(conn, connID)
}

func (c *ConnTracker) CloseConnByInbound(inbound string) int {
	c.access.Lock()
	defer c.access.Unlock()

	var toClose []*ConnectionInfo
	for _, connInfo := range c.connections {
		if connInfo.Inbound == inbound {
			toClose = append(toClose, connInfo)
		}
	}
	closedCount := 0
	for _, connInfo := range toClose {
		c.unlinkConnLocked(connInfo.ID, connInfo)
		if connInfo.Conn != nil {
			connInfo.Conn.Close()
		}
		if connInfo.PacketConn != nil {
			connInfo.PacketConn.Close()
		}
		closedCount++
	}
	return closedCount
}

func (c *ConnTracker) untrackConnection(connID string) {
	c.access.Lock()
	defer c.access.Unlock()
	ci, ok := c.connections[connID]
	if !ok {
		return
	}
	c.unlinkConnLocked(connID, ci)
}

// shouldUntrackIOErr reports whether err indicates the connection is done (peer closed, reset, etc.).
func shouldUntrackIOErr(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, io.EOF) {
		return true
	}
	var ne net.Error
	if errors.As(err, &ne) {
		return !ne.Temporary()
	}
	return true
}

func (c *ConnTracker) createWrappedConn(conn net.Conn, connID string) *wrappedConn {
	return &wrappedConn{
		Conn:    conn,
		tracker: c,
		connID:  connID,
	}
}

func (c *ConnTracker) createWrappedPacketConn(conn network.PacketConn, connID string) *wrappedPacketConn {
	return &wrappedPacketConn{
		PacketConn: conn,
		tracker:    c,
		connID:     connID,
	}
}

type wrappedConn struct {
	net.Conn
	tracker     *ConnTracker
	connID      string
	untrackOnce sync.Once
}

func (w *wrappedConn) doUntrack() {
	w.untrackOnce.Do(func() {
		w.tracker.untrackConnection(w.connID)
	})
}

func (w *wrappedConn) Read(b []byte) (int, error) {
	n, err := w.Conn.Read(b)
	if shouldUntrackIOErr(err) {
		w.doUntrack()
	}
	return n, err
}

func (w *wrappedConn) Write(b []byte) (int, error) {
	n, err := w.Conn.Write(b)
	if err != nil && shouldUntrackIOErr(err) {
		w.doUntrack()
	}
	return n, err
}

func (w *wrappedConn) Close() error {
	w.doUntrack()
	return w.Conn.Close()
}

func (w *wrappedConn) Upstream() any {
	return w.Conn
}

type wrappedPacketConn struct {
	network.PacketConn
	tracker     *ConnTracker
	connID      string
	untrackOnce sync.Once
}

func (w *wrappedPacketConn) doUntrack() {
	w.untrackOnce.Do(func() {
		w.tracker.untrackConnection(w.connID)
	})
}

func (w *wrappedPacketConn) ReadPacket(buffer *buf.Buffer) (destination M.Socksaddr, err error) {
	dest, err := w.PacketConn.ReadPacket(buffer)
	if shouldUntrackIOErr(err) {
		w.doUntrack()
	}
	return dest, err
}

func (w *wrappedPacketConn) WritePacket(buffer *buf.Buffer, destination M.Socksaddr) error {
	err := w.PacketConn.WritePacket(buffer, destination)
	if err != nil && shouldUntrackIOErr(err) {
		w.doUntrack()
	}
	return err
}

func (w *wrappedPacketConn) Close() error {
	w.doUntrack()
	return w.PacketConn.Close()
}

func (w *wrappedPacketConn) Upstream() any {
	return w.PacketConn
}
