variable "tags" {
  description = "Tags to apply to all infrastructure"
  type        = map
}

variable "vpc_cidr_block" {
  description = "CIDR block describing the IP address range of the VPC"
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "The number of AZs you want to create subnets in"
  default     = 2
}

variable "private_subnet_size" {
  description = "The number of bits you want to extend the VPC CIDR block by, for your private subnets"
  default     = 8
}

variable "public_subnet_size" {
  description = "The number of bits you want to extend the VPC CIDR block by, for your private subnets"
  default     = 8
}

# Fetch AZs in the current region
data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create var.az_count private subnets, each in a different AZ
resource "aws_subnet" "private" {
  count             = "${var.az_count}"
  cidr_block        = "${cidrsubnet(aws_vpc.main.cidr_block, var.private_subnet_size, count.index)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id            = "${aws_vpc.main.id}"
  tags              = var.tags
}

# Create var.az_count public subnets, each in a different AZ
resource "aws_subnet" "public" {
  count                   = "${var.az_count}"
  cidr_block              = "${cidrsubnet(aws_vpc.main.cidr_block, var.public_subnet_size, var.az_count + count.index)}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id                  = "${aws_vpc.main.id}"
  map_public_ip_on_launch = true
  tags                    = var.tags
}

# IGW for the public subnet
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"
  tags   = var.tags
}



resource "aws_eip" "nat_eip" {
  count      = "${var.az_count}"
  vpc        = true
  depends_on = ["aws_internet_gateway.gw"]
  tags       = var.tags
}

# Create a NAT gateway with an EIP for each private subnet to get internet connectivity
#
# resource "aws_nat_gateway" "gw" {
#   count         = "${var.az_count}"
#   subnet_id     = "${element(aws_subnet.public.*.id, count.index)}"
#   allocation_id = "${element(aws_eip.gw.*.id, count.index)}"
#   tags          = var.tags
# }


data "aws_ami" "nat_ami" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = "amzn-ami-vpc-nat.*"
}

resource "aws_instance" "nat" {
  count         = var.az_count
  ami           = "${data.aws_ami.nat_ami.id}"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[count.index].id
  tags          = var.tags
}

resource "aws_security_group" "nat_sg" {
  count = var.az_count
  name  = "nat-instance-sg-${aws_instance.nat[count.index].id}"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [aws_subnet.private[count.index].cidr_block]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [aws_subnet.private[count.index].cidr_block]
  }
  egress {
    protocol    = "tcp"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]

  }
  tags = var.tags
}

# Create a new route table for the private subnets, the nat_instance module will
# add a route to make it route non-local traffic through the NAT gateway to the
# internet
resource "aws_route_table" "public_subnet_rt" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  tags = var.tags
}

# Route the public subnet's traffic through the IGW by default
resource "aws_route" "internet_access" {
  count                  = var.az_count
  route_table_id         = aws_route_table.public_subnet_rt[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# Explicitly associate the newly created route tables to the public subnets
# (so they don't default to the main route table)
resource "aws_route_table_association" "public_subnet_rta" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_subnet_rt[count.index].id
}


resource "aws_route_table" "private_subnet_rt" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  tags = var.tags
}

# Route the private subnet's traffic through the NAT instance by default
resource "aws_route" "default_to_nat_instance" {
  count                  = var.az_count
  route_table_id         = aws_route_table.private_subnet_rt[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  instance_id            = aws_instance.nat[count.index].id
}

# Explicitly associate the newly created route tables to the private subnets
# (so they don't default to the main route table)
resource "aws_route_table_association" "private_subnet_rta" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_subnet_rt[count.index].id
}

output "vpc_id" {
  value = aws_vpc.main.id
}
output "vpc_cidr_block" {
  value = aws_vpc.main.cidr_block
}
output "public_subnet_ids" {
  value = aws_subnet.public.*.id
}
output "public_subnet_cidr_blocks" {
  value = aws_subnet.public.*.cidr_block
}
output "private_subnet_ids" {
  value = aws_subnet.private.*.id
}
output "private_subnet_cidr_blocks" {
  value = aws_subnet.private.*.cidr_block
}
output "internet_gateway_id" {
  value = aws_internet_gateway.gw.id
}
output "private_route_table_ids" {
  value = aws_route_table.private_subnet_rt.*.id
}

output "public_route_table_ids" {
  value = aws_route_table.public_subnet_rt.*.id
}
output "nat_instance_ids" {
  value = aws_instance.nat.*.id
}
