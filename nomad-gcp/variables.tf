variable "zone" {
  type        = string
  description = "GCP compute zone to deploy nomad clients into (e.g us-east1-a)"
}

variable "region" {
  type        = string
  description = "GCP region to deploy nomad clients into (e.g us-east1)"
}

variable "network" {
  type        = string
  default     = "default"
  description = "Network to deploy nomad clients into"
}

variable "unsafe_disable_mtls" {
  type        = bool
  default     = false
  description = "Disables mTLS between nomad client and servers. Compromises the authenticity and confidentiality of client-server communication. Should not be set to true in any production setting"
}

variable "server_endpoint" {
  type        = string
  description = "Hostname:port of nomad control plane"
}

variable "blocked_cidrs" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks to block access to from inside nomad jobs"
}

variable "min_replicas" {
  type        = number
  default     = 1
  description = "Minimum number of nomad clients when scaled down"
}

variable "max_replicas" {
  type        = number
  default     = 4
  description = "Max number of nomad clients when scaled up"
}

variable "target_cpu_utilization" {
  type        = number
  default     = 0.5
  description = "Target CPU utilization to trigger autoscaling"
}

variable "machine_type" {
  type        = string
  default     = "n2d-standard-8" # AMD Rome | 8vCPU | 32GiB
  description = "Instance type for nomad clients"
}

variable "assign_public_ip" {
  type        = bool
  default     = true
  description = "Assign public IP"
}

variable "preemptible" {
  type        = bool
  default     = false
  description = "Whether or not to use preemptible nodes"
}

variable "disk_type" {
  type        = string
  default     = "pd-ssd"
  description = "Root disk type. Can be 'pd-standard', 'pd-ssd', 'pd-balanced' or 'local-ssd'"
}

variable "disk_size_gb" {
  type        = number
  default     = 300
  description = "Root disk size in GB"
}
