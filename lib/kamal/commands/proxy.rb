class Kamal::Commands::Proxy < Kamal::Commands::Base
  delegate :argumentize, :optionize, to: Kamal::Utils
  delegate :container_name, :app_port, to: :proxy_config

  attr_reader :proxy_config

  def initialize(config)
    super
    @proxy_config = config.proxy
  end

  def run
    docker :run,
      "--name", container_name,
      "--network", "kamal",
      "--detach",
      "--restart", "unless-stopped",
      *proxy_config.publish_args,
      "--volume", "/var/run/docker.sock:/var/run/docker.sock",
      *proxy_config.config_volume.docker_args,
      *config.logging_args,
      proxy_config.image
  end

  def start
    docker :container, :start, container_name
  end

  def stop(name: container_name)
    docker :container, :stop, name
  end

  def start_or_run
    combine start, run, by: "||"
  end

  def deploy(service, target:)
    docker :exec, container_name, "kamal-proxy", :deploy, service, *optionize({ target: "#{target}:#{app_port}" }), *proxy_config.deploy_command_args
  end

  def remove(service, target:)
    docker :exec, container_name, "kamal-proxy", :remove, service, *optionize({ target: "#{target}:#{app_port}" })
  end

  def info
    docker :ps, "--filter", "name=^#{container_name}$"
  end

  def version
    pipe \
      docker(:inspect, container_name, "--format '{{.Config.Image}}'"),
      [ :cut, "-d:", "-f2" ]
  end

  def logs(since: nil, lines: nil, grep: nil, grep_options: nil)
    pipe \
      docker(:logs, container_name, (" --since #{since}" if since), (" --tail #{lines}" if lines), "--timestamps", "2>&1"),
      ("grep '#{grep}'#{" #{grep_options}" if grep_options}" if grep)
  end

  def follow_logs(host:, grep: nil, grep_options: nil)
    run_over_ssh pipe(
      docker(:logs, container_name, "--timestamps", "--tail", "10", "--follow", "2>&1"),
      (%(grep "#{grep}"#{" #{grep_options}" if grep_options}) if grep)
    ).join(" "), host: host
  end

  def remove_container
    docker :container, :prune, "--force", "--filter", "label=org.opencontainers.image.title=kamal-proxy"
  end

  def remove_image
    docker :image, :prune, "--all", "--force", "--filter", "label=org.opencontainers.image.title=kamal-proxy"
  end

  def remove_host_directory
    remove_directory config.proxy_directory
  end

  def cleanup_traefik
    chain \
      docker(:container, :stop, "traefik"),
      combine(
        docker(:container, :prune, "--force", "--filter", "label=org.opencontainers.image.title=Traefik"),
        docker(:image, :prune, "--all", "--force", "--filter", "label=org.opencontainers.image.title=Traefik")
      )
  end
end
