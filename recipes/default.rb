if node['user'] && node['user']['id']
  include_recipe 'homebrew::default'

  user_name = node['user']['id']
  home_dir = Etc.getpwnam(user_name).dir
else
  include_recipe "homebrewalt::default"

  user_name = node['current_user']
  home_dir = node['etc']['passwd'][user_name]['dir']
end

#http://solutions.treypiepmeier.com/2010/02/28/installing-mysql-on-snow-leopard-using-homebrew/
require 'pathname'

    ["homebrew.mxcl.mysql55.plist" ].each do |plist|
        plist_path = File.expand_path(plist, File.join('~', 'Library', 'LaunchAgents'))
        if File.exists?(plist_path)
            log "mysql55 plist found at #{plist_path}"
            execute "unload the plist (shuts down the daemon)" do
                command %'launchctl unload -w #{plist_path}'
                user user_name
            end
        else
            log "Did not find plist at #{plist_path} don't try to unload it"
        end
    end

PASSWORD = node["mysql55_root_password"] || node["mysql_root_password"]
# The next two directories will be owned by WS_USER
DATA_DIR = "/usr/local/var/mysql55"
PARENT_DATA_DIR = "/usr/local/var"

[ "#{home_dir}/Library/LaunchAgents",
  PARENT_DATA_DIR,
  DATA_DIR ].each do |dir|
  directory dir do
    owner user_name
    action :create
  end
end

if node['user'] && node['user']['id']
  homebrew_tap 'homebrew/versions'
else
  homebrewalt_tap 'homebrew/versions'
end

package "homebrew/versions/mysql55" do
  action [:install, :upgrade]
end

execute "copy over the plist" do
    command %'cp /usr/local/Cellar/mysql55/5.*/homebrew.mxcl.mysql55.plist ~/Library/LaunchAgents/'
    user user_name
end

ruby_block "mysql_install_db" do
  block do
    active_mysql = Pathname.new("/usr/local/bin/mysql55").realpath
    basedir = (active_mysql + "../../").to_s
    data_dir = "/usr/local/var/mysql55"
    installdb = Mixlib::ShellOut.new("mysql_install_db --verbose --user=#{user_name} --basedir=#{basedir} --datadir=#{DATA_DIR} --tmpdir=/tmp && chown #{user_name} #{data_dir}")
    installdb.run_command
    if installdb.exitstatus != 0
      raise("Failed initializing mysqldb")
    end
  end
  not_if { File.exists?("/usr/local/var/mysql55/mysql/user.MYD")}
end

execute "start the daemon" do
  command %'launchctl load -w ~/Library/LaunchAgents/homebrew.mxcl.mysql55.plist'
  user user_name
end

ruby_block "Checking that mysql is running" do
  block do
    Timeout::timeout(60) do
      until File.exists?("/tmp/mysql.sock")
        sleep 1
      end
    end
  end
end

mysql_path=`ls -d  /usr/local/Cellar/mysql55/*`.strip

execute "set the root password to the default" do
    command "#{mysql_path}/bin/mysqladmin -uroot password #{PASSWORD}"
    not_if "#{mysql_path}/bin/mysql -uroot -p#{PASSWORD} -e 'show databases'"
    only_if "#{mysql_path}/bin/mysql -uroot -e 'show databases'"
end

execute "brew link mysql55 --force" do
  not_if { File.exist?("/usr/local/bin/mysql") }
end
