# S-UI Plus

Advanced web panel and management UI for [SagerNet/sing-box](https://github.com/sagernet/sing-box).

**s-ui-plus** is a maintained fork of the community backup [admin8800/s-ui](https://github.com/admin8800/s-ui) (last upstream snapshot around v1.4.1), with English-first documentation, fork-specific install URLs, an [HTTP API guide](docs/API.md), and optional **single source IP** enforcement per proxy client.

> **Disclaimer:** For personal learning and lawful use only. Do not use this software for illegal purposes.

## Quick overview

| Feature | Supported |
| -------- | :--: |
| Multiple protocols | Yes |
| Multiple languages (UI) | Yes |
| Multiple clients / inbounds | Yes |
| Advanced routing UI | Yes |
| Client traffic and system status | Yes |
| Subscription links (plain / JSON / Clash + info) | Yes |
| Dark / light theme | Yes |
| HTTP API (session + token) | Yes |

## Supported platforms

| Platform | Architectures | Status |
| -------- | ------------- | ------ |
| Linux | amd64, arm64, armv7, armv6, armv5, 386, s390x | Supported |
| Windows | amd64, 386, arm64 | Supported |
| macOS | amd64, arm64 | Experimental |

## Defaults after install

- Panel port: `2095`
- Panel path: `/app/`
- Subscription port: `2096`
- Subscription path: `/sub/`
- Default admin username / password: `admin` (change immediately)

## Install or upgrade (latest)

### Linux / macOS

```sh
bash <(curl -Ls https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/install.sh)
```

### Windows

1. Download the latest Windows build from [GitHub Releases](https://github.com/callmeAsghar/s-ui-plus/releases/latest).
2. Extract the ZIP.
3. Run `install-windows.bat` as Administrator.
4. Follow the installer prompts.

### Install a specific version

Append a version tag (with leading `v`) to the install command, for example `v1.0.0`:

```sh
bash <(curl -Ls https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/install.sh) v1.0.0
```

## Manual install

### Linux / macOS

1. Download the matching release tarball from [https://github.com/callmeAsghar/s-ui-plus/releases/latest](https://github.com/callmeAsghar/s-ui-plus/releases/latest).
2. Optional: fetch the latest `s-ui.sh` helper: [https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/s-ui.sh](https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/s-ui.sh).
3. Optional: copy `s-ui.sh` to `/usr/bin/s-ui` and `chmod +x /usr/bin/s-ui`.
4. Extract the tarball to your chosen directory and `cd` into it.
5. Copy `*.service` files to `/etc/systemd/system/`, then run `systemctl daemon-reload`.
6. Run `systemctl enable s-ui --now` to enable and start the panel.
7. Run `systemctl enable sing-box --now` to start sing-box when you are ready.

### Windows

1. Open [https://github.com/callmeAsghar/s-ui-plus/releases/latest](https://github.com/callmeAsghar/s-ui-plus/releases/latest).
2. Download the appropriate package (for example `s-ui-windows-amd64.zip`).
3. Extract to your chosen directory.
4. Run `install-windows.bat` as Administrator.
5. Open the panel at `http://localhost:2095/app` (path may differ if you changed the web path).

## Uninstall

```sh
sudo -i

systemctl disable s-ui --now

rm -f /etc/systemd/system/sing-box.service
systemctl daemon-reload

rm -fr /usr/local/s-ui
rm -f /usr/bin/s-ui
```

## Docker

There is no guaranteed public image for this fork. Build locally from this repository.

<details>
<summary>Docker details</summary>

### 1. Install Docker

```shell
curl -fsSL https://get.docker.com | sh
```

### 2. Build and run (Compose)

Use the provided [`docker-compose.yml`](docker-compose.yml) (build context) from the repo root:

```shell
docker compose up -d --build
```

### 3. Build and run (`docker run`)

```shell
git clone https://github.com/callmeAsghar/s-ui-plus.git
cd s-ui-plus
docker build -t s-ui-plus:local .
mkdir -p db cert && docker run -itd \
    --network host \
    -v "$PWD/db:/app/db" \
    -v "$PWD/cert:/app/cert" \
    --name s-ui-plus \
    --restart unless-stopped \
    s-ui-plus:local
```

If you publish your own image (for example `ghcr.io/callmeAsghar/s-ui-plus`), replace the image name in Compose or `docker run` accordingly.

</details>

## Run from source (development)

<details>
<summary>Build and run</summary>

### One-shot script

```shell
./runSUI.sh
```

### Clone

```shell
git clone https://github.com/callmeAsghar/s-ui-plus.git
cd s-ui-plus
```

### Frontend

See the [frontend](frontend) directory (`npm install` / `npm run build`).

### Backend

Build the frontend at least once, then:

```shell
rm -fr web/html/*
cp -R frontend/dist/ web/html/
go build -o sui main.go
./sui
```

</details>

## HTTP API

See **[docs/API.md](docs/API.md)** for authentication, `save` / `load` usage, proxy client (de)provisioning, subscription URLs, and limitations.

## UI languages

English, Persian, Vietnamese, Simplified Chinese, Traditional Chinese, Russian (panel i18n).

## Features (high level)

- Protocols: Mixed, SOCKS, HTTP, HTTPS, Direct, Redirect, TProxy; VLESS, VMess, Trojan, Shadowsocks; ShadowTLS, Hysteria, Hysteria2, Naive, TUIC; XTLS where applicable.
- Routing UI: PROXY protocol, external proxies, transparent proxy hooks, TLS and listen configuration.
- Per-client traffic limits, expiry, optional **single active source IP** (see docs).
- Online clients, inbound/outbound stats, system status.
- Subscriptions with external links; panel and sub over HTTPS with your own certificates.
- Dark / light theme.

## Environment variables

<details>
<summary>Reference</summary>

| Variable | Type | Default |
| -------- | ---- | ------- |
| `SUI_LOG_LEVEL` | `debug` / `info` / `warn` / `error` | `info` |
| `SUI_DEBUG` | boolean | `false` |
| `SUI_BIN_FOLDER` | string | `bin` |
| `SUI_DB_FOLDER` | string | `db` |
| `SINGBOX_API` | string | (empty) |

</details>

## SSL (Certbot example)

<details>
<summary>Certbot</summary>

```bash
snap install core; snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

certbot certonly --standalone --register-unsafely-without-email --non-interactive --agree-tos -d your.domain.example
```

</details>

## Credits

Original S-UI author: **alireza0**. Community backup baseline: [admin8800/s-ui](https://github.com/admin8800/s-ui).
