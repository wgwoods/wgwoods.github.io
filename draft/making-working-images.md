# Making working system images

> "Any sufficiently advanced technology is indistinguishable from magic."
>
> -- Arthur C. Clarke

> "Sometimes magic is just someone spending more time on something than anyone
> else might reasonably expect."
>
> -- R. J. Teller

## TL;DR

Making a system image from packages generally involves adding the package
contents to a new filesystem and running extra code snippets ("scriptlets")
that generate or modify files in order to make the system actually function
correctly.

This document attempts to describe and categorize scriptlets into distinct
categories based on what type of input they need and what type of output
they create. We then describe the most common types of scriptlet tasks
and propose new, efficient, machine-readable, data-driven ways to handle them.

## Background and overview

### Files: shipped and generated

There's four categories of files that you'll find in a working system image:

1. Package payloads / build artifacts (ℙ, "Pkg")
    * independent of the rest of the system
    * shipped as-is
2. Generated catalogs / caches (𝔾, "Gen")
    * determined by the rest of the system's contents
    * can be generated after depsolve
3. User configuration (ℂ, "Conf")
    * determined from **user-provided data** (and the rest of the system)
    * generated after user config is provided
        * user config may be empty/optional!
4. System-specific data (𝔻, "Sysdata")
    * depend on the system hardware OR unique per-system

The first category is easy - it's just unmodified package payloads.

The last category cannot be handled until the first boot of the image - adding
things like `machine-id` or ssh host keys makes a generic _image_ into a
unique _system_.

The other two categories are what we're concerned with here. This is the
mission-critical magic that turns a heap of build output into a working system,
and in the Fedora/RHEL world it's almost entirely handled in three places:
RPM scriptlets, `pungi`, and `anaconda`.

### An aside: moving from scripts to data

The astute reader will note that our reliance on RPM scriptlets and anaconda
magic to build images means that a large section of our mission-critical image
build process consists of a gnarly heap of shell and Lua scripts, scattered
across hundreds of packages and written by dozens of different authors over the
course of a decade or more.

A particularly astute reader might point out this situation is very similar to
one that exists in a lot of older IT organizations with decades-old
infrastructure, where everything is controlled and managed using a set of
non-standard, home-grown scripts that are a burden to maintain and nearly
impossible to improve.

A clever Red Hatter might try to sell that IT shop on the idea of migrating
their infrastructure to a nice, manageable set of Ansible playbooks.

The most astute of readers will probably realize, at this point, that I'm
proposing a very similar idea, but for our own gnarly-but-irreplaceable
home-grown infrastructure.

### Scriptlet Tasks

Broadly speaking, there's 6 tasks required to make a filesystem composed from
package payloads into a runnable system/container:

1. Add users/groups
2. Enable/disable services (and set default target)
3. Build registries, catalogs, and caches
4. Create placeholder files/directories
5. Modify system config (firewall rules, SELinux booleans, etc.)
6. Generate system-specific data (keys, certs, machine-id, etc.)

These tasks are traditionally handled in RPM scriptlets and special code in
install/build tools (`anaconda`, `lorax`, `pungi`, `livemedia-creator`, etc.)

This document attempts to define these tasks and propose ways to handle them
in a declarative fashion, rather than encoding them in opaque shell scripts.

### 1. `user` / `group`

* Packages should ship `sysusers.d` snippets
    * We'll need to hand-maintain a library of them until upstream starts
      doing this
    * Not so bad, since this stuff rarely changes

* Need to set a root password
* **TODO**: create user account(s)

## 2. `service` / `target`

* Packages should ship `systemd.preset` files
* Use anaconda logic for setting default target
* Eventually we'll want to let users override system defaults
    * Handle that by letting them throw in their own `.preset` file data

## 3. `catalog` / `cache`

THIS IS THE TRICKY ONE.

Terms:
* `item`: a file or other item that gets added to a cache or catalog.
* `catalog`: a file or database used by a component which lists other
  installed components / objects that it can use. Required.
* `cache`: an _optional_ catalog that speeds things up. Nothing will break if
  a cache is missing.
* `build`: the act of generating a new catalog. should read all input
  components and write a new, complete catalog/cache.
* `update`: the act of modifying a (possibly) existing catalog. read one or
  more input items and add them to the catalog.

#### Some proposed example configuration snippets

Just brainstormin' here.

```
[Catalog]
Name=info
Items=/usr/share/info/*.info.gz
CmdAddOne=/sbin/install-info --info-dir=/usr/share/info %i
```

```
[Catalog]
Name=ca-legacy
Output=/etc/pki/ca-trust/source/ca-bundle.legacy.crt
Config=/etc/pki/ca-trust/ca-legacy.conf
CmdBuild=/sbin/ca-legacy install
```

```
[Catalog]
Name=ca-trust
CmdBuild=/sbin/update-ca-trust
Items=/usr/share/pki/ca-trust-source/**
Items=/etc/pki/ca-trust/source/**
Output=/etc/pki/ca-trust/extracted/**
Output=/etc/pki/tls/certs/ca-bundle.crt
Output=/etc/pki/tls/certs/ca-bundle.trust.crt
Output=/etc/pki/java/cacerts
```

```
[Cache]
Name=ldconfig
Items=/usr/lib/*.so.*
CmdBuild=/sbin/ldconfig -C %o
Output=/etc/ld.so.cache
```


## 4. `placeholder` / `default`

* Create an empty directory
* Create empty placeholder file
* Copy a default configuration into place

Most (all?) of these can be handled by using `tmpfiles.d` snippets.

### Handling `/var`

_(XXX TODO: finish research and complete this section)_

* `/var/run` used to be a regular directory
* Now it's a symlink to `/run`, which is a tmpfs mounted during early boot
    * Also `/var/lock` -> `/run/lock`
    * see [introducing `/run`] for history and details
* Some packages want to put files or directories there
* But they're all temporary, by definition
* So they need to be shipped _as tmpfiles.d snippets_
* ostree deployments don't include `/var`
* `rpm-ostree compose` converts `/var` contents to a set of `tmpfiles.d` snippets
* That's probably what we should do too
* hilarious side note: some packages still package things in `/var/run`
    * `pulseaudio.spec` even has this comment:
    * `# /var/lib/pulse seems unused, can consider dropping it?  -- rex`
    * shouts to Rex Dieter, who def knows what's up

[introducing `/run`]: https://lwn.net/Articles/436012/

## 5. `sysconfig`

#### `setsebool`: Set SELinux booleans

* I'm told this can be handled from outside a running system, but I'm not sure
whether the current tooling handles it.
* May not need to fix this to make a working system

#### `firewall`: Modify firewall rules

**TODO**: how/where/when do firewall rules get modified when e.g. httpd is
installed?

#### Other `sysconfig` tasks?

**TODO**: check out what other things commonly get modified by kickstart files
and ansible playbooks.

## 6. `sysdata`

This is separate from the others because it involves creating
system-specific data; as such, these tasks **should not** run until the first
boot of the system.

* `/etc/machine-id`
    * `/usr/bin/systemd-machine-id-setup` creates this

## Appendix 1: where/when tasks are handled

Tasks listed by their current handlers:

* Scriptlets
    * Add users/groups
    * Enable/disable services
    * Modify system configuration (firewall, selinux booleans, etc.)
    * Update registries and caches
    * Create/install placeholder files/directories
    * Create system-specific data (keys, UUIDs, bootloader images, etc.)
* Anaconda magic
    * Create user accounts (`root`, regular user)
    * Add implicit requirements (`@core`, bootloader, etc.)
    * Set default systemd target


Tasks listed in the order they're performed:

1. Resolve/depsolve user requests
    * Add implicit requirements
        * Platform (bootloader etc.)
        * System services (network tools etc.)
2. Construct image
3. Finalize construction
    * Add system users/groups
    * Build registries and caches
    * Create placeholder files / copy default configs
    * Modify system settings (firewall, SELinux booleans, etc)
    * Set default target
4. Customize image
    * Enable/disable services
    * Set root password, add user account(s)
    * Other customizations (this is where Ansible-y stuff would happen)
5. First boot
    * Create system-specific data

## Appendix 2: notes on a real-world use case

These are the things that are actually in use in the `http-server` recipe:

#### known problems

* user/group (without `dbus` user everything blows up)
* `/usr/bin/update-ca-trust` and `/usr/bin/ca-legacy`
* no `default.target`

#### other missing (possibly optional) items

* Caches/Catalogs
    * `/etc/shells`
    * `/usr/sbin/alternatives` (`ld`, etc)
    * `/usr/sbin/install-info`
    * `/sbin/ldconfig`
    * `/usr/bin/gio-querymodules-${BITS} /usr/${LIBDIR}/gio/modules`
    * `glib-compile-schemas /usr/share/glib-2.0/schemas`
    * `/usr/sbin/build-locale-archive --install-langs %{_install_langs}`
        * bluuhhhh how does that get decided
    * `gtk-update-icon-cache ${ICONDIR}`
    * `/usr/bin/newaliases`
    * `/usr/bin/update-mime-database`
        * expected to fail? need to be able to ignore exit code I guess
* Services
    * Can we just enable everything as a stopgap?
* tmpfiles
    * create empty file `/var/log/tallylog`
    * create symlink `/etc/mtab` -> `/proc/mounts` (`util-linux`)
    * create /var/log/lastlog
* sysdata
    * `/etc/pki/tls/private/localhost.key`, `/etc/pki/tls/certs/localhost.crt`
        * in `mod_ssl` but probably other things want these keys/certs
    * `systemd-machine-id-setup`
* blerg what: research these more when soberer
    * `/usr/libexec/openldap/create-certdb.sh`
    * `/usr/bin/setup-nsssysinit.sh on`
    * `journalctl --update-catalog`: is this a (required) catalog update?
