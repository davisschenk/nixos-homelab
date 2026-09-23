# Star Technology upgrade runbook

Use this procedure to upgrade the Pelican-managed Star Technology server on
`mangrove`. It preserves the world and operator-managed files while replacing
the modpack files with an exact copy of the selected CurseForge server archive.

Pelican's CurseForge Generic egg extracts a new archive over the existing
volume. Its **Reinstall** action does not remove obsolete files first. A
successful install status or an updated `client.manifest.json` therefore does
not prove that the server is clean. Old mod jars can remain beside their
replacements.

## Managed and preserved data

The server UUID is
`a2858d39-5be3-4a2b-b8b4-b7b971935204`. Its live volume is:

```text
/var/lib/pelican-wings/volumes/a2858d39-5be3-4a2b-b8b4-b7b971935204
```

Replace these directories from the server archive:

- `config`
- `defaultconfigs`
- `kubejs`
- `libraries`
- `mods`

Preserve the world and server-owned state, including `world`,
`server.properties`, `user_jvm_args.txt`, `eula.txt`, allow/block lists,
operator data, logs, and backups. Do not remove the whole volume. The archive
contains default copies of `server.properties` and `user_jvm_args.txt`, so
restore the operator copies from the snapshot after reinstall.

## 1. Resolve and review the release

Find the CurseForge server-pack file, not the client-pack file. CurseForge file
metadata exposes the server file as `serverPackFileId`:

```console
curl -fsSL 'https://api.curse.tools/v1/cf/mods/924189/files?pageSize=20' |
  jq '.data[] | {
    id,
    displayName,
    serverPackFileId
  }'
```

Confirm the selected server file directly:

```console
curl -fsSL 'https://api.curse.tools/v1/cf/mods/924189/files/<server-file-id>' |
  jq '.data | {
    id,
    displayName,
    fileName,
    hashes,
    downloadUrl
  }'
```

Update `VERSION_ID` in `hosts/mangrove/default.nix`, then validate:

```console
just fmt-check
just lint
python3 -m unittest -v pkgs/pelican-reconciler/test_reconciler.py
just build
```

Open a focused PR and wait for its checks. Do not merge it yet.

## 2. Enter the maintenance window

Stop the server through Wings so Pelican records the intended power state.
Directly stopping its Docker container causes Wings to start it again.

```console
ssh mangrove '
  token=$(sudo sed -n "s/^token: //p" /var/lib/pelican-wings/config.yml)
  curl -fsS -o /dev/null -w "HTTP %{http_code}\n" \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    --data "{\"action\":\"stop\"}" \
    http://127.0.0.1:8083/api/servers/a2858d39-5be3-4a2b-b8b4-b7b971935204/power
'
```

Wait for `State=exited`, `Exit=0`, and a complete world save:

```console
ssh mangrove '
  sudo docker inspect a2858d39-5be3-4a2b-b8b4-b7b971935204 \
    --format "State={{.State.Status}} Exit={{.State.ExitCode}}"
  sudo tail -50 \
    /var/lib/pelican-wings/volumes/a2858d39-5be3-4a2b-b8b4-b7b971935204/logs/latest.log |
    grep -E "Saving worlds|All dimensions are saved"
'
```

Do not continue unless all dimensions were saved.

## 3. Back up the stopped volume

Create a local Btrfs reflink snapshot. Use a new timestamped destination and
verify that it does not already exist:

```console
upgrade_stamp=$(date -u +%Y%m%dT%H%M%SZ)
volume=/var/lib/pelican-wings/volumes/a2858d39-5be3-4a2b-b8b4-b7b971935204
snapshot=/var/lib/pelican-wings/volumes/.pre-star-upgrade-$upgrade_stamp

ssh mangrove "
  sudo test ! -e '$snapshot' &&
  sudo cp -a --reflink=always '$volume' '$snapshot' &&
  sudo du -sh '$volume' '$snapshot'
"
```

Run the off-host Restic backup and confirm both the service result and fresh
success marker:

```console
ssh mangrove 'sudo systemctl start restic-backups-persist.service'
ssh mangrove '
  sudo systemctl show restic-backups-persist.service \
    -p Result -p ExecMainStatus -p InactiveEnterTimestamp
  sudo stat -c "%y %n" \
    /var/lib/pelican-reconciler/last-restic-success
'
```

The required result is `Result=success` and `ExecMainStatus=0`.

## 4. Merge and approve production

Merge the green PR. Follow the resulting **Deploy production** Actions run.
Review the Terraform plan, then approve its protected `production`
environment only after the backups above have succeeded.

Wait for the complete workflow, including **Deploy mangrove**, to pass. NixOS
activation updates the Pelican environment but deliberately does not reinstall
the server.

Confirm the reconciler requested an operator action:

```console
ssh mangrove '
  sudo journalctl -u pelican-reconcile.service -n 50 --no-pager
'
```

The log should include:

```text
update server startup star-technology (environment)
operator action required star-technology (restart or reinstall)
```

Read only the desired version from the Pelican API. Do not print the complete
container environment because it contains a credential.

```console
ssh mangrove '
  key=$(sudo cat /run/secrets/pelican_reconciler_api_key)
  curl -fsS \
    -H "Authorization: Bearer $key" \
    -H "Accept: application/json" \
    http://127.0.0.1:8000/api/application/servers/3
' | jq -r '.attributes.container.environment.VERSION_ID'
```

## 5. Stage the old pack files

With the server still stopped and the backups verified, move the pack-managed
directories out of the live volume. Keeping them in a sibling directory makes
this step recoverable and prevents the installer from retaining stale files.

```console
volume=/var/lib/pelican-wings/volumes/a2858d39-5be3-4a2b-b8b4-b7b971935204
staged=/var/lib/pelican-wings/volumes/.pre-install-pack-$upgrade_stamp

ssh mangrove "
  sudo test ! -e '$staged' &&
  sudo install -d -m 0750 -o pelican-wings -g pelican-wings '$staged' &&
  sudo mv '$volume/config' '$staged/config' &&
  sudo mv '$volume/defaultconfigs' '$staged/defaultconfigs' &&
  sudo mv '$volume/kubejs' '$staged/kubejs' &&
  sudo mv '$volume/libraries' '$staged/libraries' &&
  sudo mv '$volume/mods' '$staged/mods'
"
```

Do not move `world` or any operator-managed root file.

## 6. Run the clean reinstall

Resolve the numeric Pelican server ID rather than assuming it is stable:

```console
server_id=$(
  ssh mangrove '
    key=$(sudo cat /run/secrets/pelican_reconciler_api_key)
    curl -fsS -G \
      -H "Authorization: Bearer $key" \
      -H "Accept: application/json" \
      --data-urlencode "filter[external_id]=nix:star-technology" \
      http://127.0.0.1:8000/api/application/servers
  ' | jq -r '
    if (.data | length) == 1
    then .data[0].attributes.id
    else error("expected exactly one Star Technology server")
    end
  '
)
test -n "$server_id"
```

Request the reinstall:

```console
ssh mangrove "
  key=\$(sudo cat /run/secrets/pelican_reconciler_api_key)
  curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' \
    -X POST \
    -H \"Authorization: Bearer \$key\" \
    -H 'Accept: application/json' \
    http://127.0.0.1:8000/api/application/servers/$server_id/reinstall
"
```

`HTTP 204` means the request was accepted, not that installation finished.
Poll until `installed` returns `1`, and confirm Wings logged completion:

```console
ssh mangrove "
  key=\$(sudo cat /run/secrets/pelican_reconciler_api_key)
  curl -fsS \
    -H \"Authorization: Bearer \$key\" \
    -H 'Accept: application/json' \
    http://127.0.0.1:8000/api/application/servers/$server_id
" | jq '.attributes.container.installed'

ssh mangrove '
  sudo journalctl -u pelican-wings.service -n 100 --no-pager |
    grep "completed installation process"
'
```

## 7. Restore operator-managed root files

The reinstall extracts archive defaults over root files in the live volume.
Restore the server-specific copies from the stopped-volume snapshot before
starting:

```console
ssh mangrove "
  sudo cp -a --reflink=auto \
    '$snapshot/server.properties' \
    '$volume/server.properties' &&
  sudo cp -a --reflink=auto \
    '$snapshot/user_jvm_args.txt' \
    '$volume/user_jvm_args.txt'
"

ssh mangrove "
  sudo cmp '$snapshot/server.properties' '$volume/server.properties' &&
  sudo cmp '$snapshot/user_jvm_args.txt' '$volume/user_jvm_args.txt' &&
  sudo grep -E '^(server-ip|server-port|query.port)=' \
    '$volume/server.properties'
"
```

For the current deployment, the expected listener values are:

```text
query.port=25566
server-ip=0.0.0.0
server-port=25566
```

## 8. Prove the pack files are clean

Download the exact server archive to a temporary directory on the operator
machine. Verify its SHA-1 against CurseForge metadata before extracting it:

```console
verify_dir=$(mktemp -d)
curl -fsSL -o "$verify_dir/server.zip" '<downloadUrl>'

expected_sha1=$(
  curl -fsSL \
    'https://api.curse.tools/v1/cf/mods/924189/files/<server-file-id>' |
    jq -r '.data.hashes[] | select(.algo == 1) | .value'
)
printf '%s  %s\n' "$expected_sha1" "$verify_dir/server.zip" |
  sha1sum --check -

unzip -q "$verify_dir/server.zip" -d "$verify_dir/archive"
```

Compare the exact mod inventory:

```console
diff -u \
  <(cd "$verify_dir/archive" &&
    find mods -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort) \
  <(ssh mangrove \
    'sudo find /var/lib/pelican-wings/volumes/a2858d39-5be3-4a2b-b8b4-b7b971935204/mods -maxdepth 1 -type f -printf "%f\n"' |
    LC_ALL=C sort)
```

Then compare every pack-managed file by SHA-256:

```console
diff -u \
  <(cd "$verify_dir/archive" &&
    find config defaultconfigs kubejs libraries mods -type f \
      -exec sha256sum {} + | LC_ALL=C sort -k2) \
  <(ssh mangrove \
    'sudo sh -c "cd /var/lib/pelican-wings/volumes/a2858d39-5be3-4a2b-b8b4-b7b971935204 &&
      find config defaultconfigs kubejs libraries mods -type f
        -exec sha256sum {} +"' |
    LC_ALL=C sort -k2)
```

Both `diff` commands must produce no output and exit successfully. Also compare
the live and snapshot world file counts. A version string, successful installer
message, or server boot is not a substitute for these checks. Root files are
excluded from the archive comparison because the operator copies were restored
in the previous step.

## 9. Start and verify service

Start through Wings:

```console
ssh mangrove '
  token=$(sudo sed -n "s/^token: //p" /var/lib/pelican-wings/config.yml)
  curl -fsS -o /dev/null -w "HTTP %{http_code}\n" \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    --data "{\"action\":\"start\"}" \
    http://127.0.0.1:8083/api/servers/a2858d39-5be3-4a2b-b8b4-b7b971935204/power
'
```

Wait for the new `logs/latest.log` to report `Done`. Verify Wings,
Infrarust, the container, and the public route:

```console
ssh mangrove '
  sudo systemctl is-active pelican-wings infrarust
  sudo docker inspect a2858d39-5be3-4a2b-b8b4-b7b971935204 \
    --format "State={{.State.Status}} Started={{.State.StartedAt}}"
  sudo grep -F "Done (" \
    /var/lib/pelican-wings/volumes/a2858d39-5be3-4a2b-b8b4-b7b971935204/logs/latest.log |
    tail -1
'
ssh mangrove 'nc -vz -w 5 172.19.0.1 25566'
nc -vz -w 5 star.mc.schenkenberger.dev 25565
```

Keep the local snapshots and staged pack directory until the upgraded server
has been exercised and another scheduled Restic backup has completed.
