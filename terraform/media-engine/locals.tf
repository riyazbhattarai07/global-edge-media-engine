locals {
  name = var.project_name
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnet_cidrs = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]

  # Map of profile -> ffmpeg target height/bitrate, consumed by the encoder
  # container via the PROFILE env var (the container holds the real ladder).
  supported_profiles = ["480p", "720p", "1080p", "2160p"]
}
