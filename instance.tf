provider "aws" {
  access_key = "###############"
  secret_key = "######################"
  region = "us-east-1"
}

#create a vpc
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MY_VPC"
  }
}

#create your application subnet
resource "aws_subnet" "my-app-subnet" {
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.my_vpc.id
  map_public_ip_on_launch = true
  depends_on = [aws_vpc.my_vpc]
  #creates only when the vpc is created(dependent)

  tags = {
    Name = "App_subnet"
  }

}

#Define routing table
resource "aws_route_table" "my_route-table" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "MY_Route_table"
  }
}



#Associate subnet with routing table
resource "aws_route_table_association" "App_Route_Association" {
  route_table_id =aws_route_table.my_route-table.id
  subnet_id = aws_subnet.my-app-subnet.id
}


#create internet gateway for servers to be connected to internet
resource "aws_internet_gateway" "my_IG" {
  vpc_id = aws_vpc.my_vpc.id
  depends_on = [aws_vpc.my_vpc]

  tags = {
    Name = "MY_IGW"
  }
}

#add default route in routing table to print to internet gateway
resource "aws_route" "default_route" {
  route_table_id = aws_route_table.my_route-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.my_IG.id
}

#create a security group
resource "aws_security_group" "App_SG" {
  name = "App_SG"
  vpc_id = aws_vpc.my_vpc.id
  description = "allow web inbound traffic"
  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 20
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#create a private which can be used to login to the webserver
resource "tls_private_key" "web-key" {
  algorithm = "RSA"
}

#save the key to your local system
resource "aws_key_pair" "App-Instance-key" {
  public_key = tls_private_key.web-key.public_key_openssh
  key_name = "web-key"
}

#save the key to your local system
resource "local_file" "web-key" {
  filename = "web-key.pem"
  content = tls_private_key.web-key.private_key_pem
}

#create your webserber instance
resource "aws_instance" "web" {
  ami = "ami-0be2609ba883822ec"
  instance_type = "t2.micro"
  tags = {
    Name = "WebServer1"
  }
  count = 1
  subnet_id = aws_subnet.my-app-subnet.id
  key_name = "web-key"
  security_groups = [aws_security_group.App_SG.id]

   provisioner "remote-exec" {      //execute commands at runtime
     connection {                   //local-exec
        type = "ssh"
        user = "ec2-user"
        private_key = tls_private_key.web-key.private_key_pem
        host = aws_instance.web[0].public_ip
     }
     inline = [
          "sudo yum install httpd php git -y",
          "sudo systemctl start httpd",
          "sudo systemctl enable httpd"
     ]

   }
}

#create a block volume for data persistence
resource "aws_ebs_volume" "myebs1" {
  availability_zone = aws_instance.web[0].availability_zone
  size = 1
  tags = {
    Name = "ebsvol"
}
}

#attach the volume to your instance
resource "aws_volume_attachment" "attach_ebs" {
  depends_on = [aws_ebs_volume.myebs1]
  device_name = "/dev/sdh"
  instance_id = aws_instance.web[0].id
  volume_id = aws_ebs_volume.myebs1.id
  force_detach = true
}

#mount the volume to your instance
resource "null_resource" "nullmount" {
  depends_on = [aws_volume_attachment.attach_ebs]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.web-key.private_key_pem
    host = aws_instance.web[0].public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/vineets300/Webpage1.git  /var/www/html"
    ]
  }
}

#Define s3 ID         #to store the static data from the code.
locals {
  s3_origin_id = "s3-origin"
}

#create a bucket to upload your static data like images
resource "aws_s3_bucket" "iravenibucket121" {
  bucket = "iravenibucket121"
  acl = "public-read-write"
  #region = "us-east-1"

  versioning {
    enabled = true
  }

  tags ={
    Name = "iravenibucket121"
    Environment = "Prod"
  }

provisioner "local-exec" {
  command = "git clone https://github.com/vineets300/Webpage1.git apache-web1"
  }
}

###change the name of the directory everytime you are cloning into.


#Allow public access to the bucket
resource "aws_s3_bucket_public_access_block" "public_storage" {
  bucket = "iravenibucket121"
  depends_on = [aws_s3_bucket.iravenibucket121]
  block_public_acls = false
  block_public_policy = false
}


#upload your data  to s3 bucket
resource "aws_s3_bucket_object" "Object1" {
  depends_on = [aws_s3_bucket.iravenibucket121]
  bucket = "iravenibucket121"
  key = "Demo1.PNG"
  acl = "public-read-write"
  source = "apache-web1/Demo1.PNG"
}

#create a cloudfront distribution for CDN
resource "aws_cloudfront_distribution" "tera-cloudfront1" {
  depends_on = [aws_s3_bucket_object.Object1]
  enabled = false
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  origin {
    domain_name = aws_s3_bucket.iravenibucket121.bucket_regional_domain_name
    origin_id = local.s3_origin_id
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


#Update the CDN URL to your webserver code.
resource "null_resource" "write_Image" {
  depends_on = [aws_cloudfront_distribution.tera-cloudfront1]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.web-key.private_key_pem
    host = aws_instance.web[0].public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='http://${aws_cloudfront_distribution.tera-cloudfront1.domain_name}/${aws_s3_bucket_object.Object1.key}' width='300' height='380'>\" >>/var/www/html/index.html",
      "echo \"</body>\" >>/var/www/html/index.html",
      "echo \"</html>\" >>/var/www/html/index.html",
      "EOF"
    ]
  }
}


#success message and storing the result in a file
resource "null_resource" "result" {
  depends_on = [null_resource.nullmount]
  provisioner "local-exec" {
    command = "echo The website has been deployed successfully and >> result.txt  && echo the IP of the website is  ${aws_instance.web[0].public_ip} >>result.txt"
  }
}

#Test the application
resource "null_resource" "running_the_website" {
  depends_on = [null_resource.write_Image]
  provisioner "local-exec" {
    command = "start chrome ${aws_instance.web[0].public_ip}"
  }
}




































































