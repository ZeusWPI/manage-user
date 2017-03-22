#!/usr/bin/ruby
# Script to add a new user in the Zeus LDAP

require 'fileutils'
require 'csv'
require 'rubygems'
require 'highline/import'
require 'securerandom'

# Create an ldif that can be imported intro the database
#
def create_ldif(user_name, first_name, last_name, email)
  <<-EOS.gsub(/^ {4}/, '')
    version: 1

    dn: uid=#{user_name},ou=leden,dc=kelder,dc=zeus,dc=ugent,dc=be
    cn: #{first_name}
    homedirectory: /afs/zeus.ugent.be/user/#{user_name}
    loginshell: /bin/bash
    objectclass: person
    objectclass: organizationalPerson
    objectclass: inetOrgPerson
    objectclass: posixAccount
    objectclass: top
    objectclass: shadowAccount
    sn: #{last_name}
    uid: #{user_name}
    gidNumber: 10000
    uidnumber: #{uid}
    mail: #{email}
  EOS
end

# Generate a random password
#
def random_password
  chars = ('a'..'z').to_a
  newpass = ''
  1.upto(6) do |_i|
    newpass << chars[rand(chars.size - 1)]
  end
  puts newpass
  newpass
end

# Mail a user about his password
#
def send_password_mail(user_name, email, password)
  mail_body = <<-EOS.gsub(/^ {4}/, '')
    Beste Zeus-lid,

    Uw Zeus account (#{user_name}) is aangemaakt.  Uw wachtwoord is ingesteld op #{password}.

    Om uw wachtwoord te veranderen, gelieve dit te vragen aan uw lokale sysadmin

    Met vriendelijke groeten,
    Uw Zeus-admins
  EOS
  `echo '#{mail_body}' | mail -s "Uw Zeus Account" #{email}`
end

# Simple prompt
#
def prompt(title)
  print "#{title}: "
  gets.chop
end

require 'open3'

def add_to_kerberos(user_name, password)
  stdin, stdout, _stderr = Open3.popen3 "sudo kadmin.local -q 'addprinc #{user_name}'"
  stdout.gets
  stdin.puts password
  stdout.gets
  stdin.puts password
end

# Main function, sorta
#
def main
  rootpassword = get_password('Trying to add a single user, gimme that rootpass')
  # Get a username
  user_name = prompt 'User name'

  # Read simple fields
  first_name = prompt 'First name'
  last_name = prompt 'Last name'
  email = prompt 'Email'

  do_shit(user_name, first_name, last_name, email, rootpassword)
end

def get_password(prompt = 'Enter Password')
  ask(prompt) { |q| q.echo = false }
end

def main_with_csv(filename)
  rootpassword = get_password("Bulk adding from #{filename}, gimme that rootpass")
  CSV.readlines(filename, encoding: 'utf-8').each do |line|
    first_name = line[0]
    last_name = line[1]
    email = line[2]
    user_name = line[3]

    do_shit(user_name, first_name, last_name, email, rootpassword)
  end
end

def do_shit(user_name, first_name, last_name, email, rootpassword)
  `ssh root@zeus.ugent.be -p 2222 "echo 'testing ssh connection...'"`
  if $CHILD_STATUS.exitstatus != 0
    puts 'SSH to king does not work, try enabling agent forwarding'
    exit
  end

  # Smallcaps the username
  user_name.downcase!

  # Generate a password
  password = random_password

  # Create the ldif file
  user_id = SecureRandom.uuid
  puts user_id
  ldif = create_ldif(user_name, user_id, first_name, last_name, email)
  File.open('temp.ldif', 'w') do |file|
    file.write(ldif)
  end

  # Import the ldif file, then remove it
  puts 'Running ldap...'
  `ldapadd -v -x -w #{rootpassword} -D cn=admin,dc=kelder,dc=zeus,dc=ugent,dc=be -f temp.ldif`

  FileUtils.rm 'temp.ldif'
  # Wait a bit
  # Various administrative tasks
  add_to_kerberos(user_name, password)

  `echo #{rootpassword} | kinit root/admin`

  # `aklog && pts createuser -name #{user_name} -id #{user_id}`
  `aklog`

  # `vos create clarke a user.#{user_name} 10000000`
  # `cd /afs/zeus.ugent.be/user/ && fs mkm #{user_name} user.#{user_name} -rw`
  # `cd /afs/zeus.ugent.be/user/ && fs sa #{user_name} #{user_name} all`
  # `chown -R #{user_id}:10000 /afs/zeus.ugent.be/user/#{user_name}/`
  # `chmod 755 /afs/zeus.ugent.be/user/#{user_name}/`

  # `vos create clarke a web.#{user_name} 2500000`
  # `cd /afs/zeus.ugent.be/service/web/ && fs mkm #{user_name} web.#{user_name} -rw`
  # `cd /afs/zeus.ugent.be/service/web/ && fs sa #{user_name} #{user_name} all`
  # `cd /afs/zeus.ugent.be/service/web/ && fs sa #{user_name} www-data all`
  # `chown -R #{user_id}:10000 /afs/zeus.ugent.be/service/web/#{user_name}`
  # `chmod 711 /afs/zeus.ugent.be/service/web/#{user_name}/`
  # `fs mkm /afs/zeus.ugent.be/user/#{user_name}/public_html web.#{user_name} -rw`

  # `vos create clarke a mail.#{user_name} 2500000`
  # `cd /afs/zeus.ugent.be/service/mail && fs mkm #{user_name} mail.#{user_name} -rw`
  # `cd /afs/zeus.ugent.be/service/mail/ && fs sa #{user_name} #{user_name} all`
  # `chown -R #{user_id}:10000 /afs/zeus.ugent.be/service/mail/#{user_name}`
  # `chmod 711 /afs/zeus.ugent.be/service/mail/#{user_name}/`
  # `echo #{email} > /afs/zeus.ugent.be/service/mail/#{user_name}/forward`
  # `ln -s /afs/zeus.ugent.be/service/mail/#{user_name}/forward /afs/zeus.ugent.be/user/#{user_name}/.forward`
  # add to leden mail
  `ssh -A root@zeus.ugent.be -p 2222 'echo #{user_name}@zeus.ugent.be | /var/lib/mailman/bin/add_members -r - -w n -a n leden'`

  send_password_mail user_name, email, password
end

# Run
main
# main_with_csv 'nieuweleden.csv'
