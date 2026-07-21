# Configure the Raspberry Pi kernel filter

Raspberry Pi systems install multiple kernel image variants in parallel. Without
a filter, needrestart can treat an unused image as a pending kernel upgrade.

The supplied `configs/kernel.conf` is configured for a Raspberry Pi 5 that boots
the 16 KB-page `*-2712` kernel. Do not install it unchanged on other hardware or
Raspberry Pi models.

## Verify the kernel variant

Check the running kernel before selecting a filter:

```bash
uname -r
```

The result must end in `-2712` to use the supplied active configuration. If it
ends in `-v8`, enable the commented `v8` filter in `configs/kernel.conf` and
disable the `2712` filter instead. For any other suffix, consult the
[upstream needrestart Raspberry Pi guidance](https://github.com/liske/needrestart/blob/master/README.raspberry.md)
and select the filter for the kernel that the host actually boots.

## Install and validate

Run these commands from the repository root after confirming the kernel variant:

```bash
sudo install -o root -g root -m 644 \
  Needrestart/configs/kernel.conf \
  /etc/needrestart/conf.d/kernel.conf

sudo perl -c /etc/needrestart/conf.d/kernel.conf
sudo /usr/sbin/needrestart -bkl
```

Recheck `uname -r` and the configured filter whenever the host's page-size or
kernel variant is changed.
