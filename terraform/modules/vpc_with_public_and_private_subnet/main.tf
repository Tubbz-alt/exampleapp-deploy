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
  cidr_block = var.vpc_cidr_block
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

# Route the public subnet trafic through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
}

# Create a NAT instance for each private subnet to get internet
# connectivity. Explicit dependence on the IGW to make sure that gets created
# first, so that anything else gets connectivity ASAP.

resource "aws_security_group" "nat" {
  name        = "vpc_nat"
  description = "Allow traffic to pass from the private subnet to the internet"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
  egress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "NATSG"
  })
}

data "aws_ami" "nat_instance" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = ".*amzn-ami-vpc-nat.*"
}

resource "aws_instance" "nat" {
  count             = var.az_count
  ami               = data.aws_ami.nat_instance.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  instance_type     = "t2.micro"
  #key_name                    = "${var.aws_key_name}"
  vpc_security_group_ids      = [aws_security_group.nat.id]
  subnet_id                   = aws_subnet.public[count.index].id
  associate_public_ip_address = true
  source_dest_check           = false

  tags = merge(var.tags, { "Name" : "NAT instance" })
}

# Create a new route table for the private subnets, make it route non-local
# traffic through the NAT instance to the internet
resource "aws_route_table" "private" {
  count  = "${var.az_count}"
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block  = "0.0.0.0/0"
    instance_id = aws_instance.nat[count.index].id
  }

  tags = var.tags
}

# Explicitly associate the newly created route tables to the private subnets
# (so they don't default to the main route table)
resource "aws_route_table_association" "private" {
  count          = "${var.az_count}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
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
output "route_table_ids" {
  value = aws_route_table.private.*.id
}
output "nat_instance_ids" {
  value = aws_instance.nat.*.id
}
