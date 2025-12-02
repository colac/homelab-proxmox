# Terraform for Proxmox

Deploy core infrastructure components on Proxmox homelab server.

## Improvements
Convert this to module

### Create Terraform User in Proxmox

Login to proxmox web portal and open the console to run the following commands. 
```bash
# create role and set privileges
pveum role add TerraformRole -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# create user (set <password> to a password of your choice)
pveum user add terraform@pve --password IsThisSecure?WasIn1990

# set permissions
pveum aclmod / -user terraform@pve -role TerraformRole

# create API token
# this command outputs values needed for authentication
pveum user token add terraform@pve terraform-automation --privsep 0
```

```txt
.
├── main.tf
├── variables.tf
└── vars.tfvars
```

<!-- BEGIN_TF_DOCS -->

<!-- END_TF_DOCS -->