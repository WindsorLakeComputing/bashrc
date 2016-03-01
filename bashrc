
#---------------------------------------------------------------
# Global bashrc File
#---------------------------------------------------------------

# Skip this config if we aren't in bash
[[ -n "${BASH_VERSION}" ]] || return

# Skip this config if has already loaded
if declare -f __bashrc_reload >/dev/null && [[ ${bashrc_reload_flag:-0} -eq 0 ]]
then
  return
fi

[[ -n "${bashrc_prefix}" ]] && export bashrc_prefix

#---------------------------------------------------------------
# Functions
#---------------------------------------------------------------

##
# Unsets any outstanding environment variables and unsets itself.
#
cleanup() {
  unset PROMPT_COLOR REMOTE_PROMPT_COLOR _os _id bashrc_reload_flag
  unset cleanup
}

##
# Takes json on stdin and prints the value of a given path on stdout.
#
# @param [String] json path in the form of ["one"]["two"]
json_val() {
  [[ -z "$1" ]] && printf "Usage: json_val <path>\n" && return 10

  python -c 'import sys; import json; \
    j = json.loads(sys.stdin.read()); \
    print j'$1';'
}

##
# Checks if there any upstream updates.
#
# @param -q  suppress output
# @return 0 if up to date, 1 if there are updates, and 5 if there are errors
__bashrc_check() {
  if [ "$1" == "-q" ] ; then local suppress=1 && shift ; fi

  local prefix="${bashrc_prefix:-/etc/bash}"

  if [ ! -f "${prefix}/tip.date" ] ; then
    printf ">>> File ${prefix}/tip.date does not exist so cannot check.\n"
    return 5
  fi

  local tip_date=$(cat ${prefix}/tip.date)
  local flavor=${tip_date%% *}

  case "$flavor" in
    TARBALL)
      if command -v curl >/dev/null && command -v python >/dev/null ; then
        local last_commit_date="$(curl -sSL \
          http://github.com/api/v2/json/commits/show/fnichol/bashrc/HEAD | \
          json_val '["commit"]["committed_date"]')"
        if [ "${tip_date#* }" == "$last_commit_date" ] ; then
          [[ -z "$suppress" ]] && printf -- "-----> bashrc is up to date.\n"
          return 0
        else
          [[ -z "$suppress" ]] && \
            printf -- "-----> bashrc has updates to download." && \
            printf " Use 'bashrc update' to get current.\n"
          return 1
        fi
      else
        [[ -z "$suppress" ]] && \
          printf ">>>> Can't find curl and/or python commands.\n"
        return 5
      fi
    ;;
    *)
      if command -v git >/dev/null ; then
        (cd $prefix && super_cmd git fetch --quiet 2>&1 >/dev/null)
        (cd $prefix && super_cmd git --no-pager diff --quiet --exit-code \
          --no-color master..origin/master >/dev/null)
        if [[ "$?" -eq 0 ]] ; then
          [[ -z "$suppress" ]] && printf -- "-----> bashrc is up to date.\n"
          return 0
        else
          [[ -z "$suppress" ]] && \
            printf -- "-----> bashrc has updates to download." && \
            printf " Use 'bashrc update' to get current.\n"
          return 1
        fi
      else
        [[ -z "$suppress" ]] && printf ">>>> Can't find git command.\n"
        return 5
      fi
    ;;
  esac
}

##
# Initializes bashrc profile
__bashrc_init() {
  local prefix="${bashrc_prefix:-/etc/bash}"

  local egrep_cmd=
  case "$(uname -s)" in
    SunOS)  egrep_cmd=/usr/gnu/bin/egrep  ;;
    *)      egrep_cmd=egrep               ;;
  esac

  if [[ -f "${prefix}/bashrc.local" ]] ; then
    printf "A pre-existing ${prefix}/bashrc.local file was found, using it\n"
  else
    printf -- "-----> Creating ${prefix}/bashrc.local ...\n"
    super_cmd cp "${prefix}/bashrc.local.site" "${prefix}/bashrc.local"

    local color=
    case "$(uname -s)" in
      Darwin)   color="green"   ; local remote_color="yellow" ;;
      Linux)    color="cyan"    ;;
      OpenBSD)  color="red"     ;;
      FreeBSD)  color="magenta" ;;
      CYGWIN*)  color="black"   ;;
      SunOS)
        if /usr/sbin/zoneadm list -pi | $egrep_cmd :global: >/dev/null ; then
          color="magenta" # root zone
        else
          color="cyan"    # non-global zone
        fi
        ;;
    esac

    printf "Setting prompt color to be \"$color\" ...\n"
    super_cmd sed -i"" -e "s|^#\{0,1\}PROMPT_COLOR=.*$|PROMPT_COLOR=$color|g" \
      "${prefix}/bashrc.local"
    unset color

    if [[ -n "$remote_color" ]] ; then
      printf "Setting remote prompt color to be \"$remote_color\" ...\n"
      super_cmd sed -i"" -e \
        "s|^#\{0,1\}REMOTE_PROMPT_COLOR=.*$|REMOTE_PROMPT_COLOR=$remote_color|g" \
        "${prefix}/bashrc.local"
      unset remote_color
    fi
  fi

  if [[ -n "$bashrc_local_install" ]] ; then
    local p="${HOME}/.bash_profile"

    if [[ -r "$p" ]] && $egrep_cmd -q '${HOME}/.bash/bashrc' $p 2>&1 >/dev/null ; then
      printf ">> Mention of \${HOME}/.bash/bashrc found in \"$p\"\n"
      printf ">> You can add the following lines to get sourced:\n"
      printf ">>   if [[ -s \"\${HOME}/.bash/bashrc\" ]] ; then\n"
      printf ">>     bashrc_local_install=1\n"
      printf ">>     bashrc_prefix=\${HOME}/.bash\n"
      printf ">>     export bashrc_local_install bashrc_prefix\n"
      printf ">>     source \"\${bashrc_prefix}/bashrc\"\n"
      printf ">>   fi\n"
    else
      printf -- "-----> Adding source hook into \"$p\" ...\n"
      cat >> $p <<END_OF_PROFILE
if [[ -s "\${HOME}/.bash/bashrc" ]] ; then
  bashrc_local_install=1
  bashrc_prefix="\${HOME}/.bash"
  export bashrc_local_install bashrc_prefix
  source "\${bashrc_prefix}/bashrc"
fi
END_OF_PROFILE
    fi
  else
    local p=
    case "$(uname -s)" in
      Darwin)
        p="/etc/bashrc"
        ;;
      Linux)
        if [[ -f "/etc/SuSE-release" ]] ; then
          p="/etc/bash.bashrc.local"
        else
          p="/etc/profile"
        fi
        ;;
      SunOS|OpenBSD|CYGWIN*)
        p="/etc/profile"
        ;;
      *)
        printf ">>>> Don't know how to add source hook in this operating system.\n"
        return 4
        ;;
    esac

    if $egrep_cmd -q '/etc/bash/bashrc' $p 2>&1 >/dev/null ; then
      printf ">> Mention of /etc/bash/bashrc found in \"$p\"\n"
      printf ">> You can add the following line to get sourced:\n"
      printf ">>   [[ -s \"/etc/bash/bashrc\" ]] && . \"/etc/bash/bashrc\""
    else
      printf -- "-----> Adding source hook into \"$p\" ...\n"
      cat <<END_OF_PROFILE | super_cmd tee -a $p >/dev/null
[[ -s "/etc/bash/bashrc" ]] && . "/etc/bash/bashrc"
END_OF_PROFILE
    fi
  fi
  unset p
  
  printf "\n\n"
  printf "    #---------------------------------------------------------------\n"
  printf "    # Installation of bashrc complete. To activate either exit\n"
  printf "    # this shell or type: 'source ${prefix}/bashrc'.\n"
  printf "    #\n"
  printf "    # To check for updates to bashrc, run: 'bashrc check'.\n"
  printf "    #\n"
  printf "    # To keep bashrc up to date, periodically run: 'bashrc update'.\n"
  printf "    #---------------------------------------------------------------\n\n"
}

##
# Pulls down new changes to the bashrc via git.
__bashrc_update() {
  local prefix="${bashrc_prefix:-/etc/bash}"
  local repo="github.com/fnichol/bashrc.git"

  # clear out old tarball install or legacy hg cruft
  local stash=
  if [ ! -d "$prefix/.git" ] ; then
    # save a copy of bashrc.local
    if [[ -f "$prefix/bashrc.local" ]] ; then
      stash="/tmp/bashrc.local.$$"
      super_cmd cp -p "$prefix/bashrc.local" "$stash"
    fi
    super_cmd rm -rf "$prefix"
  fi

  if [[ -d "$prefix/.git" ]] ; then
    if command -v git >/dev/null ; then
      ( builtin cd "$prefix" && super_cmd git pull origin master )
    else
      printf "\n>>>> Command 'git' not found on the path, please install a"
      printf " packge or build git from source and try again.\n\n"
      return 10
    fi
  elif command -v git >/dev/null ; then
    ( builtin cd "$(dirname $prefix)" && \
      super_cmd git clone --depth 1 git://$repo $(basename $prefix) || \
      super_cmd git clone https://$repo $(basename $prefix) )
  elif command -v curl >/dev/null && command -v python >/dev/null; then
    local tarball_install=1
    case "$(uname -s)" in
      SunOS)  local tar_cmd="$(which gtar)"  ;;
      *)      local tar_cmd="$(which tar)"   ;;
    esac
    [[ -z "$tar_cmd" ]] && \
      printf ">>>> tar command not found on path, aborting.\n" && return 13

    printf -- "-----> Git not found, so downloading tarball to $prefix ...\n"
    super_cmd mkdir -p "$prefix"
    curl -LsSf http://github.com/fnichol/bashrc/tarball/master | \
      super_cmd ${tar_cmd} xvz -C${prefix} --strip 1
  else
    printf "\n>>>> Command 'git', 'curl', or 'python' were not found on the path, please install a packge or build these packages from source and try again.\n\n"
    return 16
  fi
  local result="$?"

  # move bashrc.local back
  [[ -n "$stash" ]] && super_cmd mv "$stash" "$prefix/bashrc.local"

  if [ "$result" -ne 0 ]; then
    printf "\n>>>> bashrc could not find an update or has failed.\n\n"
    return 11
  fi

  if [[ -n "$tarball_install" ]] ; then

    printf -- "-----> Determining version date from github api ...\n"
    local tip_date="$(curl -sSL \
      http://github.com/api/v2/json/commits/show/fnichol/bashrc/HEAD | \
      python -c 'import sys; import json; j = json.loads(sys.stdin.read()); print j["commit"]["committed_date"];')"
    if [ "$?" -ne 0 ] ; then tip_date="UNKNOWN" ; fi
    super_cmd bash -c "(printf \"TARBALL $tip_date\" > \"${prefix}/tip.date\")"
    __bashrc_reload
    printf -- "\n\n-----> bashrc was updated and reloaded.\n"
  else

    local old_file="/tmp/bashrc.date.$$"
    if [[ -f "$prefix/tip.date" ]] ; then
      super_cmd mv "$prefix/tip.date" "$old_file"
    else
      touch "$old_file"
    fi

    local git_cmd=$(which git)
    super_cmd bash -c "( builtin cd $prefix && \
      $git_cmd log -1 --pretty=\"format:%h %ci\" > $prefix/tip.date)"

    if ! diff -q "$old_file" "$prefix/tip.date" >/dev/null ; then
      local old_rev=$(awk '{print $1}' $old_file)
      local new_rev=$(awk '{print $1}' $prefix/tip.date)
      printf "\n#### Updates ####\n-----------------\n"
      ( builtin cd $prefix && super_cmd git --no-pager log \
        --pretty=format:'%C(yellow)%h%Creset - %s %Cgreen(%cr)%Creset' \
        --abbrev-commit --date=relative $old_rev..$new_rev )
      printf "\n-----------------\n\n"
      __bashrc_reload
      printf -- "\n\n-----> bashrc was updated and reloaded.\n"
    else
      printf -- "\n-----> bashrc is already up to date and current.\n"
    fi

    super_cmd rm -f "$old_file"
  fi

  if [[ -z "$(cat $prefix/tip.date)" ]] ; then
    super_cmd rm -f "$prefix/tip.date"
  fi
}

##
# Reloads bashrc profile
__bashrc_reload() {
  bashrc_reload_flag=1
  printf "\n" # give bashrc source line more prominence
  source "${bashrc_prefix:-/etc/bash}/bashrc"
  printf -- "-----> bashrc was reload at $(date +%F\ %T\ %z).\n"
  unset bashrc_reload_flag
}

##
# Displays the version of the bashrc profile
__bashrc_version() {
  local ver=
  # Echo the version and date of the profile
  if [[ -f "${bashrc_prefix:-/etc/bash}/tip.date" ]] ; then
    ver="$(cat ${bashrc_prefix:-/etc/bash}/tip.date)"
  elif command -v git >/dev/null ; then
    ver="$(cd ${bashrc_prefix:-/etc/bash} && \
      git log -1 --pretty='format:%h %ci')"
  else
    ver="UNKNOWN"
  fi
  printf "bashrc ($ver)\n\n"
}


##
# CLI for the bash profile.
bashrc() {
  local command="$1"
  shift

  case "$command" in
    check)    __bashrc_check $@;;
    init)     __bashrc_init $@;;
    reload)   __bashrc_reload $@;;
    update)   __bashrc_update $@;;
    version)  __bashrc_version $@;;
    *)  printf "usage: bashrc (check|init|reload|update|version)\n" && return 10 ;;
  esac
}

#  ---------------------------------------------------------------------------
#
#  Description:  This file holds all my BASH configurations and aliases
#
#  Sections:
#  1.   Environment Configuration
#  2.   Make Terminal Better (remapping defaults and adding functionality)
#  3.   File and Folder Management
#  4.   Searching
#  5.   Process Management
#  6.   Networking
#  7.   System Operations & Information
#  8.   Web Development
#  9.   Reminders & Notes
#
#  ---------------------------------------------------------------------------

#   -------------------------------
#   1.  ENVIRONMENT CONFIGURATION
#   -------------------------------

#   Change Prompt
#   ------------------------------------------------------------
    export PS1="________________________________________________________________________________\n| \w @ \h (\u) \n| => "
    export PS2="| => "

#   Set Paths
#   ------------------------------------------------------------
    export PATH="$PATH:/usr/local/bin/"
    export PATH="/usr/local/git/bin:/sw/bin/:/usr/local/bin:/usr/local/:/usr/local/sbin:/opt/rh/python27/root/usr/bin:/usr/local/mysql/bin:$PATH"

#   Set Default Editor
#   ------------------------------------------------------------
    export EDITOR=/usr/bin/vim

#   Set default blocksize for ls, df, du
#   from this: http://hints.macworld.com/comment.php?mode=view&cid=24491
#   ------------------------------------------------------------
    export BLOCKSIZE=1k

#   Add color to terminal
#   (this is all commented out as I use Mac Terminal Profiles)
#   from http://osxdaily.com/2012/02/21/add-color-to-the-terminal-in-mac-os-x/
#   ------------------------------------------------------------
   export CLICOLOR=1
   export LSCOLORS=ExFxBxDxCxegedabagacad


#   -----------------------------
#   2.  MAKE TERMINAL BETTER
#   -----------------------------

alias cp='cp -iv'                           # Preferred 'cp' implementation
alias mv='mv -iv'                           # Preferred 'mv' implementation
alias mkdir='mkdir -pv'                     # Preferred 'mkdir' implementation
alias ll='ls -FGlAhp'                       # Preferred 'ls' implementation
alias less='less -FSRXc'                    # Preferred 'less' implementation
cd() { builtin cd "$@"; ll; }               # Always list directory contents upon 'cd'
alias cd..='cd ../'                         # Go back 1 directory level (for fast typers)
alias ..='cd ../'                           # Go back 1 directory level
alias ...='cd ../../'                       # Go back 2 directory levels
alias .3='cd ../../../'                     # Go back 3 directory levels
alias .4='cd ../../../../'                  # Go back 4 directory levels
alias .5='cd ../../../../../'               # Go back 5 directory levels
alias .6='cd ../../../../../../'            # Go back 6 directory levels
alias edit='subl'                           # edit:         Opens any file in sublime editor
alias f='open -a Finder ./'                 # f:            Opens current directory in MacOS Finder
alias ~="cd ~"                              # ~:            Go Home
alias c='clear'                             # c:            Clear terminal display
alias which='type -all'                     # which:        Find executables
alias path='echo -e ${PATH//:/\\n}'         # path:         Echo all executable Paths
alias show_options='shopt'                  # Show_options: display bash options settings
alias fix_stty='stty sane'                  # fix_stty:     Restore terminal settings when screwed up
alias cic='set completion-ignore-case On'   # cic:          Make tab-completion case-insensitive
mcd () { mkdir -p "$1" && cd "$1"; }        # mcd:          Makes new Dir and jumps inside
trash () { command mv "$@" ~/.Trash ; }     # trash:        Moves a file to the MacOS trash
ql () { qlmanage -p "$*" >& /dev/null; }    # ql:           Opens any file in MacOS Quicklook Preview
alias DT='tee ~/Desktop/terminalOut.txt'    # DT:           Pipe content to file on MacOS Desktop

#   lr:  Full Recursive Directory Listing
#   ------------------------------------------
alias lr='ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less'

#   mans:   Search manpage given in agument '1' for term given in argument '2' (case insensitive)
#           displays paginated result with colored search terms and two lines surrounding each hit.             Example: mans mplayer codec
#   --------------------------------------------------------------------
    mans () {
        man $1 | grep -iC2 --color=always $2 | less
    }

#   showa: to remind yourself of an alias (given some part of it)
#   ------------------------------------------------------------
    showa () { /usr/bin/grep --color=always -i -a1 $@ ~/Library/init/bash/aliases.bash | grep -v '^\s*$' | less -FSRXc ; }


#   -------------------------------
#   3.  FILE AND FOLDER MANAGEMENT
#   -------------------------------

zipf () { zip -r "$1".zip "$1" ; }          # zipf:         To create a ZIP archive of a folder
alias numFiles='echo $(ls -1 | wc -l)'      # numFiles:     Count of non-hidden files in current dir
alias make1mb='mkfile 1m ./1MB.dat'         # make1mb:      Creates a file of 1mb size (all zeros)
alias make5mb='mkfile 5m ./5MB.dat'         # make5mb:      Creates a file of 5mb size (all zeros)
alias make10mb='mkfile 10m ./10MB.dat'      # make10mb:     Creates a file of 10mb size (all zeros)

#   cdf:  'Cd's to frontmost window of MacOS Finder
#   ------------------------------------------------------
    cdf () {
        currFolderPath=$( /usr/bin/osascript <<EOT
            tell application "Finder"
                try
            set currFolder to (folder of the front window as alias)
                on error
            set currFolder to (path to desktop folder as alias)
                end try
                POSIX path of currFolder
            end tell
EOT
        )
        echo "cd to \"$currFolderPath\""
        cd "$currFolderPath"
    }

#   extract:  Extract most know archives with one command
#   ---------------------------------------------------------
    extract () {
        if [ -f $1 ] ; then
          case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar e $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)     echo "'$1' cannot be extracted via extract()" ;;
             esac
         else
             echo "'$1' is not a valid file"
         fi
    }


#   ---------------------------
#   4.  SEARCHING
#   ---------------------------

alias qfind="find . -name "                 # qfind:    Quickly search for file
ff () { /usr/bin/find . -name "$@" ; }      # ff:       Find file under the current directory
ffs () { /usr/bin/find . -name "$@"'*' ; }  # ffs:      Find file whose name starts with a given string
ffe () { /usr/bin/find . -name '*'"$@" ; }  # ffe:      Find file whose name ends with a given string

#   spotlight: Search for a file using MacOS Spotlight's metadata
#   -----------------------------------------------------------
    spotlight () { mdfind "kMDItemDisplayName == '$@'wc"; }


#   ---------------------------
#   5.  PROCESS MANAGEMENT
#   ---------------------------

#   findPid: find out the pid of a specified process
#   -----------------------------------------------------
#       Note that the command name can be specified via a regex
#       E.g. findPid '/d$/' finds pids of all processes with names ending in 'd'
#       Without the 'sudo' it will only find processes of the current user
#   -----------------------------------------------------
    findPid () { lsof -t -c "$@" ; }

#   memHogsTop, memHogsPs:  Find memory hogs
#   -----------------------------------------------------
    alias memHogsTop='top -l 1 -o rsize | head -20'
    alias memHogsPs='ps wwaxm -o pid,stat,vsize,rss,time,command | head -10'

#   cpuHogs:  Find CPU hogs
#   -----------------------------------------------------
    alias cpu_hogs='ps wwaxr -o pid,stat,%cpu,time,command | head -10'

#   topForever:  Continual 'top' listing (every 10 seconds)
#   -----------------------------------------------------
    alias topForever='top -l 9999999 -s 10 -o cpu'

#   ttop:  Recommended 'top' invocation to minimize resources
#   ------------------------------------------------------------
#       Taken from this macosxhints article
#       http://www.macosxhints.com/article.php?story=20060816123853639
#   ------------------------------------------------------------
    alias ttop="top -R -F -s 10 -o rsize"

#   my_ps: List processes owned by my user:
#   ------------------------------------------------------------
    my_ps() { ps $@ -u $USER -o pid,%cpu,%mem,start,time,bsdtime,command ; }


#   ---------------------------
#   6.  NETWORKING
#   ---------------------------

alias myip='curl ip.appspot.com'                    # myip:         Public facing IP Address
alias netCons='lsof -i'                             # netCons:      Show all open TCP/IP sockets
alias flushDNS='dscacheutil -flushcache'            # flushDNS:     Flush out the DNS Cache
alias lsock='sudo /usr/sbin/lsof -i -P'             # lsock:        Display open sockets
alias lsockU='sudo /usr/sbin/lsof -nP | grep UDP'   # lsockU:       Display only open UDP sockets
alias lsockT='sudo /usr/sbin/lsof -nP | grep TCP'   # lsockT:       Display only open TCP sockets
alias ipInfo0='ipconfig getpacket en0'              # ipInfo0:      Get info on connections for en0
alias ipInfo1='ipconfig getpacket en1'              # ipInfo1:      Get info on connections for en1
alias openPorts='sudo lsof -i | grep LISTEN'        # openPorts:    All listening connections
alias showBlocked='sudo ipfw list'                  # showBlocked:  All ipfw rules inc/ blocked IPs

#   ii:  display useful host related informaton
#   -------------------------------------------------------------------
    ii() {
        echo -e "\nYou are logged on ${RED}$HOST"
        echo -e "\nAdditionnal information:$NC " ; uname -a
        echo -e "\n${RED}Users logged on:$NC " ; w -h
        echo -e "\n${RED}Current date :$NC " ; date
        echo -e "\n${RED}Machine stats :$NC " ; uptime
        echo -e "\n${RED}Current network location :$NC " ; scselect
        echo -e "\n${RED}Public facing IP Address :$NC " ;myip
        #echo -e "\n${RED}DNS Configuration:$NC " ; scutil --dns
        echo
    }


#   ---------------------------------------
#   7.  SYSTEMS OPERATIONS & INFORMATION
#   ---------------------------------------

alias mountReadWrite='/sbin/mount -uw /'    # mountReadWrite:   For use when booted into single-user

#   cleanupDS:  Recursively delete .DS_Store files
#   -------------------------------------------------------------------
    alias cleanupDS="find . -type f -name '*.DS_Store' -ls -delete"

#   finderShowHidden:   Show hidden files in Finder
#   finderHideHidden:   Hide hidden files in Finder
#   -------------------------------------------------------------------
    alias finderShowHidden='defaults write com.apple.finder ShowAllFiles TRUE'
    alias finderHideHidden='defaults write com.apple.finder ShowAllFiles FALSE'

#   cleanupLS:  Clean up LaunchServices to remove duplicates in the "Open With" menu
#   -----------------------------------------------------------------------------------
    alias cleanupLS="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"

#    screensaverDesktop: Run a screensaver on the Desktop
#   -----------------------------------------------------------------------------------
    alias screensaverDesktop='/System/Library/Frameworks/ScreenSaver.framework/Resources/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine -background'

#   ---------------------------------------
#   8.  WEB DEVELOPMENT
#   ---------------------------------------

alias apacheEdit='sudo edit /etc/httpd/httpd.conf'      # apacheEdit:       Edit httpd.conf
alias apacheRestart='sudo apachectl graceful'           # apacheRestart:    Restart Apache
alias editHosts='sudo edit /etc/hosts'                  # editHosts:        Edit /etc/hosts file
alias herr='tail /var/log/httpd/error_log'              # herr:             Tails HTTP error logs
alias apacheLogs="less +F /var/log/apache2/error_log"   # Apachelogs:   Shows apache error logs
httpHeaders () { /usr/bin/curl -I -L $@ ; }             # httpHeaders:      Grabs headers from web page

#   httpDebug:  Download a web page and show info on what took time
#   -------------------------------------------------------------------
    httpDebug () { /usr/bin/curl $@ -o /dev/null -w "dns: %{time_namelookup} connect: %{time_connect} pretransfer: %{time_pretransfer} starttransfer: %{time_starttransfer} total: %{time_total}\n" ; }


#   ---------------------------------------
#   9.  REMINDERS & NOTES
#   ---------------------------------------

#   remove_disk: spin down unneeded disk
#   ---------------------------------------
#   diskutil eject /dev/disk1s3

#   to change the password on an encrypted disk image:
#   ---------------------------------------
#   hdiutil chpass /path/to/the/diskimage

#   to mount a read-only disk image as read-write:
#   ---------------------------------------
#   hdiutil attach example.dmg -shadow /tmp/example.shadow -noverify

#   mounting a removable drive (of type msdos or hfs)
#   ---------------------------------------
#   mkdir /Volumes/Foo
#   ls /dev/disk*   to find out the device to use in the mount command)
#   mount -t msdos /dev/disk1s1 /Volumes/Foo
#   mount -t hfs /dev/disk1s1 /Volumes/Foo

#   to create a file of a given size: /usr/sbin/mkfile or /usr/bin/hdiutil
#   ---------------------------------------
#   e.g.: mkfile 10m 10MB.dat
#   e.g.: hdiutil create -size 10m 10MB.dmg
#   the above create files that are almost all zeros - if random bytes are desired
#   then use: ~/Dev/Perl/randBytes 1048576 > 10MB.dat
