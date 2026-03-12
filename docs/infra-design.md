# Infrastructure Design

## Provider Model

The project exposes a common variable interface and uses a `provider` switch to target Hetzner, AWS, or DigitalOcean. Hetzner is the default because it matches the cost target and VPS specification requested.

## Default Sizing

- CPU: 2 vCPU
- Memory: 4 GB
- OS: Ubuntu 24.04
- Network: private network where supported, public IPv4

## Managed Resources

- Network or VPC primitive
- Firewall or security group rules
- Virtual machine or droplet
- Local inventory output for Ansible

## Outputs

OpenTofu publishes server IP, provider metadata, and SSH connection details so the Ansible and shell layers can stay fully scripted.
