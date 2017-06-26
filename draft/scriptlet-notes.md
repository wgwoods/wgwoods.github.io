# SCRIPTLET NOTES

Yes, we're doing this again.

Note that I'm deliberately ignoring upgrades at the moment - this first pass
is only concerned with initial generation of images.

## Summary of items

Here's a high-level overview of the tasks handled by scriptlets.

1. Updating caches / registries
    * Define system caches & their update commands
        * ldconfig
            * cachefile=/etc/ld.so.cache
            * updater=/usr/sbin/ldconfig
            * run after assembly
        * many more..
    * Adding new items to associated registries
        * /etc/shells: tag shells as 'shell', add a line when installed
        * plymouth themes
        * new kernels
        * XML/SGML catalog files
        * `alternatives` symlinks
            * `symlink` `name` `realfile` `priority`
        * many more..
2. User / Group handling
    * Track what user/group names get used
    * Assign them UID/GID before transaction
    * Things that do `chown`: why
3. Service handling
    * Apply presets for all services
    * Have a spot in the recipe for user customized presets
4. Tempfiles, default configs, empty directories, etc.
    * Handle these with `tmpfiles.d` config snippets
    1. Initial/placeholder config files
        * Mark target path as config
        * If non-existent, copy in file (or create empty)
        * Why aren't these just shipped?
    2. Creating symlinks, device nodes, etc.
    3. Setting extended permissions (chattr, setfacl, setfattr)    
    4. Things that should be happening after firstboot runs
        * Grab a copy of /etc/localtime (`avahi` - also, why??)
5. Creating certificates or other system-specific data
    * Creating SSL certs (`cyrus-imapd`, many others)
    * `/etc/machine-id`
6. Setting SELinux booleans etc.
    * can we set these from the outside? or is this a firstboot thing?

Another major item is config/data migration, but that's only relevant when
handling updates, so we'll skip that for now.

## 1. Updating caches, registries, etc.

**NOTE**: There's a lot of things that update caches, schema, databases,
catalogs, registries, etc.

I _think_ we can break this down into sub-categories, as follows:

* **updating a cache** is optional; Everything still works if you skip this,
  but it speeds things up at first boot or during use of some other tools.
* **updating a registry** is required; some other tool will not know that
  this item exists until this action is performed. This could happen at the
  end of image assembly _or_ during firstboot, so long as it happens before
  anything tries to use any tools that use the registry.
* **building a database** is required; it's kind of the inverse of updating
  a registry. Instead of a newly installed item adding itself so external tools
  can find it, we're generating some database of things that this tool will
  use. Generally this means that the tool won't work without a valid database.
* **generating system data** is required, but _cannot happen until firstboot_,
  since the generated data is unique to this system or depends on its hardware.

There's also two styles for updaters:

* **add**: we need to give the updater a specific path or name
  to add to the registry.
* **refresh**: just run the command and it'll figure out the rest.

It might also be relevant to note whether this updater is dealing with
keys or certificates, since we might want stricter controls on that stuff.

Note that building a text file into some binary format is isomorphic to
"updating a registry". (But why wouldn't we just do that beforehand?)

### Update alternatives

* `alternatives --install`
* `update-alternatives ...`

Let's replace this with drop-in config files! e.g.:

* `/etc/alternatives.conf.d/${PROVIDER}.conf`
    * `/etc/alternatives.conf.d/cups.conf`:
    ```
    priority 40
    print         /usr/bin/lpr     /usr/bin/lpr.cups
    print-lp      /usr/bin/lp      /usr/bin/lp.cups
    print-cancel  /usr/bin/cancel  /usr/bin/cancel.cups
    [etc...]
    ```
    * `/etc/alternatives.conf.d/libjavaplugin.x86_64.conf`:
    ```
    priority 18000
    family java-1.8.0-openjdk.x86_64

    # main entry
    libjavaplugin.so.x86_64 /usr/lib64/mozilla/plugins/libjavaplugin.so  /usr/lib64/IcedTeaPlugin.so

    # "slave" entries
    javaws      /usr/bin/javaws                  /usr/bin/javaws.itweb
    javaws.1.gz /usr/share/man/man1/javaws.1.gz  /usr/share/man/man1/javaws-itweb.1.gz
    ```
    * `/etc/alternatives.conf.d/postfix.conf`:
    ```
    priority 30
    initscript postfix
    mta             /usr/bin/sendmail   /usr/sbin/sendmail.postfix
    mta-mailq       /usr/bin/mailq      /usr/bin/mailq.postfix
    mta-newaliases  /usr/bin/newaliases /usr/bin/newaliases.postfix
    mta-pam         /usr/pam.d/smtp     /etc/pam.d/smtp.postfix
    [etc...]
    ```
* `priority X` sets priority (required)
* `family FAMILYNAME` sets family name (optional, only one allowed)
* `initscript SERVICENAME` adds associated service (optional)
* `NAME SYMLINK REALFILE` is an alternatives entry (required, one or more)
* First item is the `--install` entry, with `PRIORITY` set
* All subsequent entries are `--slave` entries
* TODO: `--auto`, `--set`?

### Update caches

* `ldconfig`
* `update-desktop-database -q`
* `ca-legacy install`
* `update-ca-trust`
* `gio-querymodules-${BITS} ${LIB}/gio/modules`
* `gdk-pixbuf-query-loaders-${BITS} --update-cache`
* `gtk-query-immodules-${VERSION}-${BITS} --update-cache`
* `/usr/bin/pango-querymodules-${BITS} --update-cache`
* `dconf update`
* `ccs_update_schema`
* `mkfontscale`
* `mkfontdir`
* `hpcups-update-ppds`
* `ibus write-cache --system`
* `journalctl --update-catalog`
* `/usr/bin/texconfig-sys rehash`
* `depmod`

### Update catalog/registry

* `build-locale-archive --install-langs ${LANGS}`
* `fc-cache ${FONT_DIR}`
* `gtk-update-icon-cache ${ICON_DIR}`
* `update-mime-database ${MIME_DIR}`
* `glib-compile-schemas ${SCHEMA_DIR}`
* `xmlcatalog --add ...`
* `install-catalog --add ...`
* `install-info ...`
* `pear install --nodeps --soft --force --register-only ${PKGXML}`
* `pecl install --nodeps --soft --force --register-only --nobuild ${PKGXML}`
* `/usr/share/sblim-cmpi-base/provider-register.sh`
* `gconftool-2 --makefile-install-rule /etc/gconf/schemas/${SCHEMA}.schemas`
* `tic $NEW_TERMINFO`
* `/usr/sbin/unbound-anchor ...`
* `/usr/bin/openlmi-mof-register ...`
* `mysql_config ${LIB}/mysql/mysql_config ${BITS}`
* `mysqlbug ${LIB}/mysql/mysqlbug ${BITS}`
* `fmtutil-sys --all`
* `/usr/bin/rarian-sk-update`
* `/etc/mail/make ...`
* `newaliases??`
* `scrollkeeper-update`
* `extlinux --update`
* `systemd-tempfiles --create ${TMPFILES_CONF}`
* `/usr/sbin/t1libconfig --force`
* `xorg-x11-fonts-update-dirs`
* `weak-modules --add-modules`
* `dot -c`

### Generate system-specific data

* `gencert /etc/httpd/alias`
* `/usr/libexec/openldap/create-certdb.sh` XXX: is this system-specific?

### Update system-specific caches

* `udevadm hwdb --update` # XXX: upgrade-only?

### SELinux management

* `sepolgen-ifgen`

## 2. add users/groups

This happens all over the place; AFAICT every instance of this can/should
be handled by shipping a `sysusers.d(5)` snippet instead.

We can use `systemd-sysusers(8)` to make the needed changes from the outside,
or write a compatible tool if we don't want to require `systemd` on the
build host.

## 3. Manage services

Similarly: enabling/disabling services should be handled by the use of
`systemd.preset(5)` files - one (or more) containing the centralized distro
defaults, and (optionally) a user-provided `.preset` file (maybe generated
from a `[services.presets]` section in the recipe).

Again, these settings can be applied to a system from the outside using
the existing systemd tools, if they're present on the build host.

As for scriptlets that do start/stop/reload/etc - these things aren't relevant
unless you're working inside a running system. We may want some logic adjacent
to this when we start working on handling system updates but for initial system
construction it's not relevant.

### BELOW HERE IS STILL IN PROGRESS OK THANKS
-------

## 4. install initial configuration files

* Create an empty placeholder
    * `touch /etc/audit/rules.d/audit.rules`
* Copy an example/default config into place if not there
    * abrt-harvest-vmcore:
    ```
    # Copy the configuration file to plugin's directory
    test -f /etc/abrt/abrt-harvest-vmcore.conf && {
        mv -b /etc/abrt/abrt-harvest-vmcore.conf /etc/abrt/plugins/vmcore.conf
    }
    ```
* Generate a config dynamically for some reason
    * openldap-servers:
    ```
    /usr/libexec/openldap/convert-config.sh -f /usr/share/openldap-servers/slapd.ldif
    ```
    * pki-base:
    ```
    echo "Configuration-Version: 10.3.3" > /etc/pki/pki.version
    ```




## 6. Adding ourselves to /etc/shells or similar

* bash, tcsh, zsh, etc.
* `pk11install` and friends (`modutil` etc)

## Generating certificates or other system-specific data

* Certificate generation:
    * `/usr/libexec/openldap/generate-server-cert.sh`
    * `/usr/bin/vmware-guestproxycerttool ...`
    * Also dovecot, radiusd, cyrus-imapd, mod_ssl, ...
* System-specific data
    * `/usr/lib/systemd/systemd-random-seed save` # XXX at firstboot?
    * `systemd-machine-id-setup`

## Hardware twiddling (drivers)

OpenIPMI-modalias:

    if [ -f "/var/run/OpenIPMI.first_installation" ]; then
        if /usr/bin/udevadm info --export-db | grep -qie 'acpi:IPI0'; then
            /sbin/modprobe ipmi_si || :;
            /sbin/modprobe ipmi_devintf || :;
            /sbin/modprobe ipmi_msghandler || :;
            /usr/bin/rm -f /var/run/OpenIPMI.first_installation || :;
            /usr/bin/udevadm settle
        fi
    fi

qemu-kvm:

    udevadm control --reload >/dev/null 2>&1 || :
    sh /etc/sysconfig/modules/kvm.modules &> /dev/null || :
        udevadm trigger --subsystem-match=misc --sysname-match=kvm --action=add || :

## SELinux

(Open question: which of these things can we do without having the target's policy loaded?)

* `setsebool`
* `restorecon` / `fixfiles`
* `semodule`
* `sepolgen-ifgen`
* `semanage import`
* `load_policy`

## Weird shit to check back in on

* `cgdcbxd` is weird:
    ```
    ### START scriptlet-dump/cgdcbxd.Trigger.1.sh ###
    grep -q iscsid /etc/cgrules.conf
    if [ $? -ne 0 ]
    then
        echo "*:iscsid net_prio cgdcb-4-3260" >> /etc/cgrules.conf
    fi
    ```

* gdb:
    ```
    for i in $(echo bin lib $(basename /usr/lib64) sbin|tr ' ' '\n'|sort -u);do
      src="/usr/share/gdb/auto-load/$i"
      dst="/usr/share/gdb/auto-load//usr/$i"
      if test -d $src -a ! -L $src;then
        if ! rmdir 2>/dev/null $src;then
          mv -n $src/* $dst/
          rmdir $src
        fi
      fi
    done

    # It would break RHEL-5 by leaving excessive files for the doc subpackage.
    ```
* grub2-tools
* ipa-client update
* java-openjdk is insaane
* what's this `/var/lib/rpm-state/gconf` stuff
* libvirt-cim: ugh
* nss-pam-ldapd: WHAT IS HAPPENING
* nss in general: WHAT WHY
* openldap-servers: gnarly stuff happening
* perl-XML-SAX: what's this `save_parsers()` stuff about
* php-pear.Trigger
* systemtap: certs, uprobes, etc.
* `tex*`: _please kill me_

## Summarizing what we need

Data classes:

* Config
* Database
* Registry
    * Users/Groups
* Cache
* System-Data
    * Certificate
* Logfile

Actions:

* Create
* Copy
* Generate
* Update

Hooks:

* Post-assembly
* Firstboot


Flags:

* Optional (cache)
* Required (registry)
* Crypto
    * this is mostly just informational
* "Why didn't we just ship this?"
    * Content-dependent
        * `ld.so.cache`, registries, alternatives
    * Arch-specific
        * ???
    * Host-specific (or hardware-specific)
        * `/boot/initramfs-$(uname -r).img`
    * System-unique
        * `/etc/machine-id`, keys, certs

Modes:

* Initial creation / supply default
* Update


## Possible schema

### Cache updater
```
[cache.IDENTIFIER]
Name=""
Description=""
CacheFile="/path/to/cache"
UpdateCommand="/bin/executable --update-cache"

```

### Registry handler
```
[registry.IDENTIFIER]
Name=""
Description=""
RegistryFile="/path/to/registry"
# NOTE: AddCommand might need some way to save the system's ID for the
# newly added item, so that we can pass it to RemoveCommand later...
AddCommand="/bin/addthingy %i"
RemoveCommand="/bin/rmthingy %i"
```
