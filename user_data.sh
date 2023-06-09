 #!/bin/bash
  yum update -y
  yum install httpd wget zip -y
#####################################################################
  wget https://www.tooplate.com/zip-templates/2133_moso_interior.zip
  unzip 2133_moso_interior.zip
  cp -r 2133_moso_interior/* /var/www/html/
  systemctl start httpd
  systemctl enable httpd