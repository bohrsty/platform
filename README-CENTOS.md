## Preparation of the CentOS 7 image

* install minimal package selection in setup
* add user teamwire
  * `useradd teamwire`
  * `passwd teamwire`
* install required packages
  * `yum install git ansible NetworkManager-glib nm-connection-editor.x86_64 libsemanage-python policycoreutils-python python2-pip`
* checkout platform repository from github
  * become user teamwire (`su - teamwire`)
  * git clone https://github.com/teamwire/platform.git


**sudo isn't configured by default on CentOS, use the following command to execute ansible from /home/teamwire/platform/ansible (root password required):**
`ansible-playbook -i hosts site.yml -K --become-method=su`
