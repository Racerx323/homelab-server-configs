# reconYa Installation and systemd Service

This guide installs [Dyneteq/reconya](https://github.com/Dyneteq/reconya) using
the project's one-shot installer and configures it to run in the background,
restart after failures, and start automatically at boot.

The commands below are intended for a Linux system that uses `systemd`, such as
Debian, Ubuntu, or Raspberry Pi OS.

## 1. Install required tools

```bash
sudo apt update
sudo apt install -y curl
```

## 2. Download and install reconYa

Run the official one-shot installer from the home directory of the account that
will own the installation:

```bash
cd "$HOME"
curl -sL https://raw.githubusercontent.com/Dyneteq/reconya/master/install.sh | sh
```

The installer:

- Detects Linux and the machine architecture.
- Downloads the current release from GitHub.
- Creates the `~/reconya` directory.
- Copies `.env.example` to `.env` when necessary.

Inspect the resulting installation:

```bash
cd "$HOME/reconya"
ls -lha
```

The executable name depends on the CPU architecture:

| Architecture | Typical executable |
| --- | --- |
| Raspberry Pi 64-bit / ARM64 | `reconya-linux-arm64` |
| Intel or AMD 64-bit | `reconya-linux-amd64` |

Confirm the executable that was actually installed:

```bash
find "$HOME/reconya" -maxdepth 1 -type f -name 'reconya-linux-*' -executable -print
```

Do not copy an executable name from another system. The `ExecStart` path in the
service must exactly match the file reported by this command.

## 3. Configure reconYa

Edit the configuration:

```bash
nano "$HOME/reconya/.env"
```

At minimum, replace the default login password and ensure the JWT secret is
unique:

```dotenv
LOGIN_USERNAME=admin
LOGIN_PASSWORD=replace-with-a-strong-password
JWT_SECRET_KEY=replace-with-a-long-random-secret
```

Generate a suitable secret with:

```bash
openssl rand -base64 48
```

Keep `.env` private:

```bash
chmod 600 "$HOME/reconya/.env"
```

## 4. Test the application manually

For an ARM64 system:

```bash
cd "$HOME/reconya"
sudo ./reconya-linux-arm64
```

For an AMD64 system:

```bash
cd "$HOME/reconya"
sudo ./reconya-linux-amd64
```

Open `http://SERVER-IP:3008` in a browser. Press `Ctrl+C` after confirming that
the application starts successfully.

## 5. Create the systemd service

Determine the exact home directory and executable path:

```bash
printf 'Installation directory: %s\n' "$HOME/reconya"
find "$HOME/reconya" -maxdepth 1 -type f -name 'reconya-linux-*' -executable -print
```

Create the service:

```bash
sudo nano /etc/systemd/system/reconya.service
```

For a Raspberry Pi user named `pi` with the ARM64 executable, use:

```ini
[Unit]
Description=reconYa network reconnaissance service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/pi/reconya
ExecStart=/home/pi/reconya/reconya-linux-arm64
User=root
Group=root
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Change both `/home/pi/reconya` paths if reconYa was installed under a different
account. Change `reconya-linux-arm64` to `reconya-linux-amd64` on an AMD64
system.

ReconYa is run as root here because its upstream launch instructions use
`sudo`, and network discovery may require privileged networking operations.

## 6. Enable and start the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now reconya.service
```

Check its status:

```bash
sudo systemctl status reconya.service
```

Confirm that the web interface responds:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:3008/
```

An `HTTP 200`, `302`, or `303` response confirms that the web server is
reachable. Do not use `curl -I` for this check: `-I` sends an HTTP `HEAD`
request, which reconYa may reject with `405 Method Not Allowed` even though the
application is running normally.

Then open:

```text
http://SERVER-IP:3008
```

## 7. Service management and logs

Start, stop, or restart reconYa:

```bash
sudo systemctl start reconya.service
sudo systemctl stop reconya.service
sudo systemctl restart reconya.service
```

Show recent logs:

```bash
sudo journalctl -u reconya.service -n 100 --no-pager
```

Follow logs live:

```bash
sudo journalctl -u reconya.service -f
```

Confirm that reconYa is enabled at boot:

```bash
sudo systemctl is-enabled reconya.service
```

## 8. Updating reconYa

Stop the service and preserve the current configuration and data:

```bash
sudo systemctl stop reconya.service
cp "$HOME/reconya/.env" "$HOME/reconya/.env.backup"
sudo cp -a "$HOME/reconya/data" "$HOME/reconya/data.backup"
```

Check the project's current release and update instructions before replacing
the binary. After installing the new binary, verify its filename because the
service's `ExecStart` value must match it exactly.

Restart and inspect the service:

```bash
sudo systemctl daemon-reload
sudo systemctl restart reconya.service
sudo systemctl status reconya.service
```

## 9. Troubleshooting

### Status 203/EXEC or "No such file or directory"

This means `ExecStart` does not identify an executable file at that exact path.
Compare the installed binary with the service:

```bash
find "$HOME/reconya" -maxdepth 1 -type f -name 'reconya-linux-*' -executable -print
sudo systemctl cat reconya.service
```

For example, a Raspberry Pi commonly installs:

```text
/home/pi/reconya/reconya-linux-arm64
```

Using `reconya-linux-amd64` in that service will fail.

After correcting the service:

```bash
sudo systemctl daemon-reload
sudo systemctl restart reconya.service
sudo journalctl -u reconya.service -n 50 --no-pager
```

### Port 3008 is already in use

```bash
sudo ss -ltnp | grep ':3008'
```

Stop the conflicting process or change reconYa's configured port if the
installed release supports that setting.

### `curl -I` returns `405 Method Not Allowed`

The following response does not mean reconYa has failed:

```text
HTTP/1.1 405 Method Not Allowed
```

The `curl -I` option sends a `HEAD` request, and reconYa may not provide a
handler for that HTTP method. Test the application with a normal `GET` request:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:3008/
```

An `HTTP 200`, `302`, or `303` response indicates that reconYa is reachable.
You can also verify it by opening `http://SERVER-IP:3008` in a browser.

### Configuration or database permission errors

Because the service runs as root, data created during service operation may be
owned by root. Inspect ownership and logs:

```bash
ls -lha "$HOME/reconya"
ls -lha "$HOME/reconya/data"
sudo journalctl -u reconya.service -n 100 --no-pager
```

### Service repeatedly restarts

Stop the restart loop before troubleshooting:

```bash
sudo systemctl stop reconya.service
sudo journalctl -u reconya.service -n 100 --no-pager
```

Verify the `WorkingDirectory`, `ExecStart`, `.env`, executable permission, and
port availability before starting it again.

## References

- [Dyneteq/reconya repository](https://github.com/Dyneteq/reconya)
- [Official one-shot installer](https://github.com/Dyneteq/reconya/blob/master/install.sh)
