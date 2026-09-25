# Custom CA certificates

Drop any internal/private **root CA** certificates here as `*.crt` or `*.pem`
files. During the Packer build they are uploaded to the guest and registered
with `update-ca-certificates` by `scripts/10-install-custom-ca.sh`.

This directory must exist even when empty, because the Packer `file`
provisioner uploads it unconditionally — an absent source path fails the build.
If you have no custom CAs, just leave the placeholder in place and the install
script will detect there are no certificates and skip gracefully.
