# Manage an ISC DHCP server
class dhcp (
  Array[String] $dnsdomain = $dhcp::params::dnsdomain,
  Array[String] $v6_dnsdomain = $dnsdomain,
  Array[String] $nameservers = [],
  Array[String] $v6_nameservers = [],
  Boolean $failover = false,
  Optional[Boolean] $bootp = undef,
  Array[String] $ntpservers = [],
  Optional[Array[String]] $interfaces = undef,
  Optional[Array[String]] $v6_interfaces = undef,
  String $interface = 'NOTSET',
  String $v6_interface = 'NOTSET',
  Integer[0] $default_lease_time = 43200,
  Integer[0] $max_lease_time = 86400,
  String $dnskeyname = 'rndc-key',
  Optional[String] $dnsupdatekey = undef,
  Optional[String] $dnsupdateserver = undef,
  Boolean $omapi = true,
  Optional[String] $omapi_name = undef,
  String $omapi_algorithm = 'HMAC-MD5',
  Optional[String] $omapi_key = undef,
  Optional[String] $pxeserver = undef,
  String $pxefilename = $dhcp::params::pxefilename,
  Optional[String] $ipxe_filename = undef,
  Optional[Integer[0]] $mtu  = undef,
  Hash[String, String] $bootfiles = $dhcp::params::bootfiles,
  String $logfacility = 'local7',
  String $v6_logfacility = $logfacility,
  Boolean $dhcp_monitor = true,
  Stdlib::Absolutepath $dhcp_dir = $dhcp::params::dhcp_dir,
  Boolean $manage_dhcp_dir = $dhcp::params::manage_dhcp_dir,
  Optional[Stdlib::Filemode] $conf_dir_mode = $dhcp::params::conf_dir_mode,
  String $packagename = $dhcp::params::packagename,
  String $servicename = $dhcp::params::servicename,
  String $v6_servicename = $dhcp::params::v6_servicename,
  $option_static_route = undef,
  Variant[Array[String], Optional[String]] $options = undef,
  Variant[Array[String], Optional[String]] $v6_options = undef,
  Boolean $authoritative = false,
  Boolean $v6_authoritative = $authoritative,
  String $dhcp_root_user = 'root',
  String $dhcp_root_group = $dhcp::params::root_group,
  Boolean $ddns_updates = false,
  Optional[String] $ddns_domainname = undef,
  Optional[String] $ddns_rev_domainname = undef,
  Enum['none', 'interim', 'standard'] $ddns_update_style = 'interim',
  Optional[Boolean] $client_updates = undef,
  Hash[String, Hash] $pools = {},
  Hash[String, Hash] $hosts = {},
  Variant[Array[String], Optional[String]] $includes = undef,
  Variant[Array[String], Optional[String]] $v6_includes = undef,
  String $config_comment = 'dhcpd.conf',
  String $v6_config_comment = 'dhcpd6.conf',
) inherits dhcp::params {

  # In case people set interface instead of interfaces work around
  # that. If they set both, use interfaces and the user is a unwise
  # and deserves what they get.
  if $interface != 'NOTSET' and $interfaces == undef {
    $dhcp_interfaces = [ $interface ]
  } elsif $interface == 'NOTSET' and $interfaces == undef {
    fail ("You need to set \$interfaces in ${module_name}")
  } else {
    $dhcp_interfaces = $interfaces
  }
  # Same for v6, except optional
  if $v6_interface != 'NOTSET' and $v6_interfaces == undef {
    $dhcp6_interfaces = [ $v6_interface ]
  } else {
    $dhcp6_interfaces = $v6_interfaces
  }
  $v6 = ($dhcp6_interfaces != undef)

  # See https://tools.ietf.org/html/draft-ietf-dhc-failover-12 for why BOOTP is
  # not supported in the failover protocol. Relay agents *can* be made to work
  # so $bootp can be explicitly set to true to override this default.
  if $bootp == undef {
    $bootp_real = !$failover
  } else {
    $bootp_real = $bootp
  }

  $dnsupdateserver_real = pick_default($dnsupdateserver, $nameservers[0])
  if $ddns_updates or $dnsupdatekey {
    unless $dnsupdateserver_real =~ String[1] {
      fail('dnsupdateserver or nameservers parameter is required to enable ddns')
    }
  }

  package { $packagename:
    ensure   => installed,
  }

  if $manage_dhcp_dir {
    file { $dhcp_dir:
      owner   => $dhcp_root_user,
      group   => $dhcp_root_group,
      mode    => $conf_dir_mode,
      require => Package[$packagename],
    }
  }

  # Only debian and ubuntu have this style of defaults for startup.
  case $facts['os']['family'] {
    'Debian': {
      file{ '/etc/default/isc-dhcp-server':
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        before  => Package[$packagename],
        notify  => Service[$servicename],
        content => template('dhcp/debian/default_isc-dhcp-server'),
      }
    }
    'RedHat': {
      include systemd
      systemd::dropin_file { 'interfaces.conf':
        unit           => 'dhcpd.service',
        content        => template('dhcp/redhat/systemd-dropin.conf.erb'),
        notify_service => true,
      }
    }
    /^(FreeBSD|DragonFly)$/: {
      $interfaces_line = join($dhcp_interfaces, ' ')
      augeas { 'set listen interfaces':
        context => '/files/etc/rc.conf',
        changes => "set dhcpd_ifaces '\"${interfaces_line}\"'",
        before  => Package[$packagename],
        notify  => Service[$servicename],
      }
    }
    default: {
    }
  }

  concat { "${dhcp_dir}/dhcpd.conf":
    owner   => $dhcp_root_user,
    group   => $dhcp_root_group,
    mode    => '0644',
    require => Package[$packagename],
    notify  => Service[$servicename],
  }

  concat::fragment { 'dhcp.conf+01_main.dhcp':
    target  => "${dhcp_dir}/dhcpd.conf",
    content => template('dhcp/dhcpd.conf.erb'),
    order   => '01',
  }

  concat::fragment { 'dhcp.conf+20_includes':
    target  => "${dhcp_dir}/dhcpd.conf",
    content => template('dhcp/dhcpd.conf.includes.erb'),
    order   => '20',
  }

  concat { "${dhcp_dir}/dhcpd.hosts":
    owner   => $dhcp_root_user,
    group   => $dhcp_root_group,
    mode    => '0644',
    require => Package[$packagename],
    notify  => Service[$servicename],
  }

  concat::fragment { 'dhcp.hosts+01_main.hosts':
    target  => "${dhcp_dir}/dhcpd.hosts",
    content => "# static DHCP hosts\n",
    order   => '01',
  }

  if $v6 {
    if $v6_servicename == 'NI' {
      fail('IPv6 support not yet implemented for this OS')
    }

    concat { "${dhcp_dir}/dhcpd6.conf":
      owner   => $dhcp_root_user,
      group   => $dhcp_root_group,
      mode    => '0644',
      require => Package[$packagename],
      notify  => Service[$v6_servicename],
    }

    concat::fragment { 'dhcp6.conf+01_main.dhcp6':
      target  => "${dhcp_dir}/dhcpd6.conf",
      content => template('dhcp/dhcpd6.conf.erb'),
      order   => '01',
    }

    concat::fragment { 'dhcp6.conf+20_includes':
      target  => "${dhcp_dir}/dhcpd6.conf",
      content => template('dhcp/dhcpd6.conf.includes.erb'),
      order   => '20',
    }

    concat { "${dhcp_dir}/dhcpd6.hosts":
      owner   => $dhcp_root_user,
      group   => $dhcp_root_group,
      mode    => '0644',
      require => Package[$packagename],
      notify  => Service[$v6_servicename],
    }

    concat::fragment { 'dhcp6.hosts+01_main.hosts':
      target  => "${dhcp_dir}/dhcpd6.hosts",
      content => "# static DHCP hosts\n",
      order   => '01',
    }
  }

  create_resources('dhcp::pool', $pools)
  create_resources('dhcp::host', $hosts)

  service { $servicename:
    ensure => running,
    enable => true,
  }

  if $v6 and ($v6_servicename != $servicename) {
    service { $v6_servicename:
      ensure => running,
      enable => true,
    }
  }

}
