# make sure that you have setup all variables before required this file
#
# Usage example:
# set :use_mod_rails, true # it will overwride some cap recipes to be compatible with passenger
# set :app_symlinks, [ 'public/system', *REQUIRED_CONFIG_FILES ]
# require File.dirname(__FILE__) + '/deploy/extra_capistrano_tasks'

unless Capistrano::Configuration.respond_to?(:instance)
  abort "requires Capistrano 2"
end

Capistrano::Configuration.instance.load do
  _cset :use_mod_rails, false
  _cset :app_symlinks,  []
  
  after 'deploy:update',      'deploy:cleanup' # remove old releases
  after 'deploy:update_code', 'deploy:symlink_shared'
  
  namespace :log do
    desc "Tail log files. Usage: LOG='current_env.log' [LINES=50] [REAL_TIME=false]" 
    task :apps, :roles => :app do
      file = ENV['LOG'] || "#{rails_env}.log"
      run_tail "#{shared_path}/log/#{file}"
    end

    # [LINES=50] [REAL_TIME=false]
    def run_tail(file, lines=nil, real_time=nil)
      lines ||= ENV['LINES'] || 50
      f = (ENV['REAL_TIME'] || real_time) ? '-f' : ''

      run "tail #{f} #{file} -n #{lines}" do |channel, stream, data|
        puts  # for an extra line break before the host name
        puts "#{channel[:host]}: #{data}" 
        break if stream == :err
      end
    end
  end

  namespace :install do
    desc 'Install Rails gem'
    task :rails, :roles => :app do
      sudo "gem install rails --no-rdoc --no-ri"
    end    
    
    desc 'Install rails apps required gems'
    task :rails_required_gems, :roles => :app do
      run "cd #{current_path}; #{sudo} rake gems:install"
    end
  end
  
  namespace :deploy do
    if use_mod_rails
      [:start, :stop, :cold].each do |t|
        desc "#{t} task is a no-op with mod_rails"
        task t, :roles => :app do ; end
      end

      # Overwrite the default method
      desc 'Tell Passenger to restart the app & restart God/AM Poller system'
      task :restart, :roles => :app do
        run "touch #{current_path}/tmp/restart.txt"
      end
    end    
    
    desc 'Symlink shared files and folders on each release. Usage: set :symlinks, [\'config/database.yml\']'
    task :symlink_shared, :roles => :app do
      abort 'Symlinks havent been setup' unless exists?(:app_symlinks)
      proceed_app_symlinks(app_symlinks)
    end

    desc 'Overwrite the default method'
    task :finalize_update, :roles => :app do
      run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)

      run "rm -rf #{latest_release}/log #{latest_release}/tmp"
      proceed_app_symlinks ['log', 'tmp']

      if fetch(:normalize_asset_timestamps, true)
        stamp = Time.now.utc.strftime("%Y%m%d%H%M.%S")
        asset_paths = %w(images stylesheets javascripts).map { |p| "#{latest_release}/public/#{p}" }.join(" ")
        run "find #{asset_paths} -exec touch -t #{stamp} {} ';'; true", :env => { "TZ" => "UTC" }
      end
    end
    
    def proceed_app_symlinks(symlns)
      out = symlns.collect do |name|
               "ln -sf #{shared_path}/#{name} #{release_path}/#{name}"
             end.join(' && ')
      run out
    end    
  end
end

# Copyright (c) 2009 Zhurbiy Oleg ( Ol.keene ), released under the MIT license