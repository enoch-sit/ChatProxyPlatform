variable "project" {
  type    = string
  default = "chatproxy"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_id" {
  type        = string
  description = "VPC to place the WireGuard instance in"
}

variable "subnet_id" {
  type        = string
  description = "Public subnet for the WireGuard instance"
}

variable "instance_type" {
  type        = string
  default     = "t4g.nano"
  description = "EC2 instance type — t4g.nano is sufficient for WireGuard"
}

variable "wg_listen_port" {
  type        = number
  default     = 51820
  description = "WireGuard UDP listen port"
}

variable "wg_subnet" {
  type        = string
  default     = "10.10.0.0/24"
  description = "WireGuard VPN subnet CIDR"
}

variable "wg_server_ip" {
  type        = string
  default     = "10.10.0.1/24"
  description = "WireGuard server VPN IP with CIDR"
}

variable "peers" {
  type = list(object({
    name       = string
    public_key = string
    allowed_ip = string # e.g. "10.10.0.2/32"
  }))
  default     = []
  description = "List of WireGuard peers (workstations). Add public keys after generating them on each workstation."
}
