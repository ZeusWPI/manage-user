#!/usr/bin/ruby
# Script to add a new user in the Zeus LDAP

require 'fileutils'

# Find a new user id
#
def find_new_user_id
  id = File.readlines("last_id").join.to_i + 1 
  File.open("last_id", "w") {|f| f << id }
  id
end

# Create an ldif that can be imported intro the database
#
def create_ldif user_name,uid, first_name, last_name 
  return <<-EOS.gsub(/^ {4}/, "")
    version: 1

    dn: uid=#{user_name},ou=leden,dc=kelder,dc=zeus,dc=ugent,dc=be
    cn: #{first_name}
    homedirectory: /afs/zeus.ugent.be/user/#{user_name}
    loginshell: /bin/bash
    objectclass: person
    objectclass: organizationalPerson
    objectclass: posixAccount
    objectclass: top
    objectclass: shadowAccount
    sn: #{last_name}
    uid: #{user_name}
    gidNumber: 10000
    uidnumber: #{uid}
  EOS
end

# Generate a random password
#
def random_password
  chars = ("a".."z").to_a
  newpass = ""
  1.upto(6) do
    |i| newpass << chars[rand(chars.size-1)]
  end
  puts newpass
  newpass
end

# Mail a user about his password
#
def send_password_mail user_name, email, password
  mail_body = <<-EOS.gsub(/^ {4}/, "")
    Uw zeus account (#{user_name}) is aangemaakt en uw wachtwoord is ingesteld
    op #{password}. Gelieve in te loggen via ssh op zeus.ugent.be, poort 2222
    en met het commando passwd uw wachtwoord te veranderen. In geval van
    problemen of vragen, mail naar jasper@zeus.ugent.be.
  EOS
  #`echo '#{mail_body}' | mail -s "Uw Zeus Account" #{email}`
end

# Simple prompt
#
def prompt title
  print "#{title}: "
  gets.chop
end

require 'open3'

def add_to_kerberos(user_name, password)
  stdin, stdout, stderr = Open3.popen3 "sudo kadmin.local -q 'addprinc #{user_name}'" 
  stdout.gets
  stdin.puts password
  stdout.gets
  stdin.puts password
end

# Main function, sorta
#
def main
  # Get a username
  user_name = prompt "User name"

  # Read simple fields
  first_name = prompt "First name"
  last_name = prompt "Last name"
  email = prompt "Email"

  # Generate a password

  password = random_password

  # Create the ldif file
  user_id = find_new_user_id
  ldif = create_ldif(user_name,user_id, first_name, last_name)
  File.open "temp.ldif", "w" do |file|
    file.write(ldif)
  end

  # Import the ldif file, then remove it
  puts "Running ldap..."
  `ldapadd -v -x -W -D cn=admin,dc=kelder,dc=zeus,dc=ugent,dc=be -f temp.ldif`
  FileUtils.rm "temp.ldif"
  # Wait a bit

  puts "adding user in kerberos"
  # Various administrative tasks
  add_to_kerberos(user_name, password)
 
  `kinit root/admin && aklog && pts createuser #{user_name} #{user_id}`
  `vos create clarke a user.#{user_name} 10000000`
  `cd /afs/zeus.ugent.be/user/ && fs mkm #{user_name} user.#{user_name} -rw`
  `cd /afs/zeus.ugent.be/user/ && fs sa #{user_name} #{user_name} all`
end

# Run
main

