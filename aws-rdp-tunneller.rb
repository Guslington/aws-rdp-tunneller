#!/usr/bin/env ruby

require 'aws-sdk'
require 'securerandom'
require 'cfpropertylist'
require 'openssl'
require 'base64'

def get_list_of_windows_servers
  servers = Hash.new
  resp = $ec2.describe_instances(
    filters:
      [
        { name: 'tag:Environment', values: [$environment_name] },
        { name: 'instance-state-name', values: ['running'] },
        { name: 'platform', values: ['windows'] },
      ]
  )
  resp.reservations.each_with_index do |res,index|
    servers[index] = Hash.new
    res.instances.each do |i|
      tag  = i.tags.select {|t| t.key == 'Name' }
      name = tag[0].value
      servers[index].merge!(name: name, id: i.instance_id.gsub('i-',''), instance_id: i.instance_id, ip: i.private_ip_address, uuid: SecureRandom.uuid, port: rand(49152..65535))
    end
  end
  return servers
end

def get_bastion
  resp = $ec2.describe_instances(
    filters:
      [
        { name: 'tag:Environment', values: [$environment_name] },
        { name: 'instance-state-name', values: ['running'] },
        { name: 'tag:Name', values: ["#{$environment_name}-bastion-xx"] },
      ]
  )
  resp.reservations[0].instances[0].public_dns_name
end

def get_windows_passwords
  $servers.each do |key,value|
    resp = $ec2.get_password_data({ instance_id: value[:instance_id] })
    private_key = OpenSSL::PKey::RSA.new(File.read($privatekey))
    if resp.password_data != ""
      $servers[key][:password] = private_key.private_decrypt(Base64.decode64(resp.password_data))
    else
      puts "WARN: Unable to retrieve password for #{value[:name]} #{value[:instance_id]}"
      $servers.delete(key)
    end
  end
end

def create_plist
  $data["bookmarkorder.ids"] = []
  $servers.each { |key,server| add_remote_desktop_client(key) }
  $data["preferences.resolutions"] = [ "@Size(640 480)", "@Size(800 600)", "@Size(1024 768)", "@Size(1280 720)", "@Size(1280 1024)", "@Size(1600 900)", "@Size(1920 1080)", "@Size(1920 1200)" ]
  $data["show_whats_new_dialog"] = 0
  $data["stored_version_number"] = "8.0.26163"

  plist = CFPropertyList::List.new
  plist.value = CFPropertyList.guess($data)
  plist.save($plist_file, CFPropertyList::List::FORMAT_BINARY)

  %x(killall cfprefsd)
end

def add_remote_desktop_client(i)
  $data["bookmarkorder.ids"] << "{#{$servers[i][:uuid]}}"
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.label"] = "#{$servers[i][:instance_id]} - #{$servers[i][:name]}"
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.hostname"] = "localhost:#{$servers[i][:port]}"
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.username"] = "Administrator"
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.resolution"] = "@Size(0 0)"
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.depth"] = "32"
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.fullscreen"] = true
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.scaling"] = false
  $data["bookmarks.bookmark.{#{$servers[i][:uuid]}}.useallmonitors"] = false
end

def add_password_to_keychain(i)
  %x(security add-internet-password -l #{$servers[i][:instance_id]} -a Administrator -s "localhost:#{$servers[i][:port]}" -w "#{$servers[i][:password].gsub('$','\$')}" -p "{#{$servers[i][:uuid]}}" -T "/Applications/Microsoft Remote Desktop.app" /Users/#{$loggedInUser}/Library/Keychains/login.keychain)
end

def delete_password_in_keychain(i)
  %x(security delete-internet-password -l #{$servers[i][:instance_id]} /Users/#{$loggedInUser}/Library/Keychains/login.keychain)
end

def setup_ssh_tunnel_bash(i)
  pid = spawn "ssh #{$sshuser}#{$bastion} -L #{$servers[i][:port]}:#{$servers[i][:ip]}:3389 -N"
  Process.detach(pid)
  $ssh_pids << pid
  puts "DEBUG: Setting up ssh session for #{$servers[i][:instance_id]} with ip #{$servers[i][:ip]} on port #{$servers[i][:port].to_i}" if $debug
end

def cleanup
  $ssh_pids.each do |pid|
    begin
      Process.kill("TERM", pid)
    rescue Errno::ESRCH => e
      puts "DEBUG: SSH PID #{pid} | #{e}"
    end
  end
  $servers.each { |key,server| delete_password_in_keychain(key) }
  File.delete($plist_file)
  puts "DEBUG: MRD PID #{$mrd_pid}"
end

until ARGV.empty?
  if ARGV.first.start_with?('-')
    case ARGV.shift
    when '-r', '--region'
      $region = ARGV.shift
    when '-e', '--environment-name'
      $environment_name = ARGV.shift
    when '-k', '--private-key'
      $privatekey = ARGV.shift
    when '-p', '--aws-profile'
      $profile = ARGV.shift
    when '-u', '--ssh-user'
      $sshuser = ARGV.shift
    end
  else
    ARGV.shift
  end
end

if !$region || !$environment_name || !$privatekey
  abort "ERROR: one or more parameters not supplied\nRequired `--environment-name`, `--region`, `--private-key`\nOptional `--ssh-user`"
end

unless !$sshuser
  $sshuser = "#{$sshuser}@"
else
  $sshuser = ""
end

if !$profile
  $ec2 = Aws::EC2::Client.new(region: $region)
else
  creds = Aws::SharedCredentials.new(profile_name: $profile)
  $ec2 = Aws::EC2::Client.new(region: $region, credentials: creds)
end

$loggedInUser = ENV['USER']
$plist_file = "/Users/#{$loggedInUser}/Library/Containers/com.microsoft.rdc.mac/Data/Library/Preferences/com.microsoft.rdc.mac.plist"
$data = Hash.new
$ssh_pids = Array.new

puts "=================================\n   Welcome to AWS-RDP-Tunneller  \n=================================\n"
puts "Type [q] to quit and cleanup\nNOTE: If script is cancelled it may leave open ssh connections and build up keys in your keychain **\n\n"
puts "INFO: Getting list of windows servers"
$servers = get_list_of_windows_servers
puts "INFO: Found #{$servers.count}"
puts "INFO: Getting passwords"
get_windows_passwords
puts "INFO: Retrieved #{$servers.count} passwords"
puts "INFO: Adding servers into Microsoft Remote Desktop"
create_plist
puts "INFO: Adding passwords into keychain"
$servers.each { |key,server| add_password_to_keychain(key) }

puts "INFO: Getting bastion address"
$bastion = get_bastion

puts "INFO: Starting Microsoft Remote Desktop"
$mrd_pid = spawn "open -na '/Applications/Microsoft Remote Desktop.app/Contents/MacOS/Microsoft Remote Desktop'"
Process.detach($mrd_pid)

puts "INFO: Setting up ssh sessions"
$servers.each { |key,server| setup_ssh_tunnel_bash(key) }

puts "\n"

loop do
  case gets.strip
  when "Q","q"
    puts "INFO: Cleaning up"
    cleanup
    puts "INFO: Exiting"
    exit 0
  else
    puts "Type [q] to quit"
  end
end
