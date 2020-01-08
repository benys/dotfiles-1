# Check for newer local version of zsh
autoload -U is-at-least
if ! is-at-least 5.2; then
    for zsh in $HOME/local/bin/zsh; do
        [[ -x $zsh ]] && exec $zsh
    done
fi

# /etc/zsh/zprofile overwrites stuff set in .zshenv
# This is kind of a hack, but not that big of a deal
[[ -e /etc/zsh/zprofile ]] && source $HOME/.zshenv

# My only FreeBSD system, pfSense, doesn't really support unicode
if [[ $OSTYPE == freebsd* ]]; then
    export TERM="${TERM%-powerline}"
fi

if [[ $TERM == *256color* && $TERM != tmux* ]]; then
    # Configure color palette on modern terminals
    print -Pn '\e]4;0;rgb:00/00/00\a\e]4;1;rgb:ab/46/42\a\e]4;2;rgb:a1/b5/6c\a\e]4;3;rgb:f7/ca/88\a\e]4;4;rgb:7c/af/c2\a\e]4;5;rgb:ba/8b/af\a\e]4;6;rgb:86/c1/b9\a\e]4;7;rgb:d8/d8/d8\a\e]4;8;rgb:58/58/58\a\e]4;9;rgb:ab/46/42\a\e]4;10;rgb:a1/b5/6c\a\e]4;11;rgb:f7/ca/88\a\e]4;12;rgb:7c/af/c2\a\e]4;13;rgb:ba/8b/af\a\e]4;14;rgb:86/c1/b9\a\e]4;15;rgb:f8/f8/f8\a\e]4;16;rgb:dc/96/56\a\e]4;17;rgb:a1/69/46\a\e]4;18;rgb:28/28/28\a\e]4;19;rgb:38/38/38\a\e]4;20;rgb:b8/b8/b8\a\e]4;21;rgb:e8/e8/e8\a\e]10;rgb:d8/d8/d8\a\e]11;rgb:00/00/00\a\e]12;rgb:d8/d8/d8\a'
elif [[ $TERM == 'linux' && -o login && ! $SSH_CONNECTION ]]; then
    # Set Linux console color palette.  See console(4).
    print -Pn '\e]P0000000\e]P1ab4642\e]P2a1b56c\e]P3f7ca88\e]P47cafc2\e]P5ba8baf\e]P686c1b9\e]P7d8d8d8\e]P8585858\e]P9ab4642\e]Paa1b56c\e]Pbf7ca88\e]Pc7cafc2\e]Pdba8baf\e]Pe86c1b9\e]Pff8f8f8'
    clear
elif [[ $TERM == 'vt220' && -o login ]]; then
    # Make serial consoles more bearable.
    # Yes, this is ugly, but I'm almost always using an xterm-compatible
    # terminal so there's no point in fighting with the limitations of an
    # ancient terminal type that I'm not actually even using.
    print 'Setting TERM=xterm'
    export TERM='xterm'
fi

# Run tmux if it's not running.  I don't exec 't' because if tmux is
# unavailable, then it will return a non-zero exit code and zsh will
# continue as a fallback; and when tmux does run and exits cleanly, I
# still want ~/.zlogout evaluated.
if [[ ! $TMUX ]]; then
    t 2>/dev/null && exit
fi

# XXX: Rename histfile
if [[ -f ~/.histfile.$HOST && ! -f ~/.history.$HOST ]]; then
    mv -f ~/.histfile.$HOST ~/.history.$HOST
elif [[ -f ~/.histfile.$HOST ]]; then
    rm -f ~/.histfile.$HOST
fi

# History settings
HISTFILE=~/.history.$HOST
HISTSIZE=10000
SAVEHIST=10000
setopt inc_append_history

if [[ ! -e $HISTFILE ]]; then
    touch $HISTFILE
    chmod 600 $HISTFILE
fi

if [[ ! -w $HISTFILE ]]; then
    echo
    echo "HISTFILE is not writable..."
    echo "Run \"s chown $USER:$(id -gn) $HISTFILE\" to fix."
    echo
fi

# Restore default redirect behavior
setopt clobber

# Enable vi keybindings
bindkey -v

# Make mode switches faster
export KEYTIMEOUT=1

# Enable history commands from emacs mode
# (just too useful)
bindkey '^P' up-history
bindkey '^N' down-history
bindkey '^R' history-incremental-pattern-search-backward
bindkey '^S' history-incremental-pattern-search-forward
stty -ixon      # make ^S available to shell

# Show user name at prompt if not one of my usual ones
zstyle ':prompt:mine' hide-users '(james|jlee|jtl|root)'

# Figure out if I'm running as a priviliged user
if [[ $EUID == 0  ]]; then
    zstyle ':prompt:mine' root true
fi
if [[ $OS == 'Windows_NT' ]] && id -Gnz | tr '\0' '\n' | grep -q '^Administrators$'; then
    zstyle ':prompt:mine' root true
fi

# Figure out if I'm running with Glue admin rights
if [[ -x $(whence klist) ]] && klist 2>&1 | grep jtl/admin > /dev/null; then
    zstyle ':prompt:mine' admin true
fi

# Fallback to flat appearance if using a stupid terminal
if [[ $TERM != *powerline* ]]; then
    zstyle ':prompt:mine' flat true
fi

# Enable my command prompt
autoload -U promptinit && promptinit
prompt mine

# Enable command autocompletion
autoload -U compinit && compinit -u

# Color list autocompletion
if [[ -x $(whence dircolors) ]]; then
    eval $(dircolors)
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
fi

# Aliases
ls --help 2>&1 | grep -- '--color' > /dev/null && alias ls='ls --color'
alias vi="$EDITOR"
unalias cp 2>/dev/null
alias mv='mv -f'
alias rm='rm -f'
alias r='eval "$(t show-environment -s)" && TERM="${${(s/ /)$(t show-options -s default-terminal)}[2]//\"/}" && exec $SHELL'
alias bigsnaps='zfs list -t snapshot -s used'
unalias suafs 2>/dev/null
unalias a 2>/dev/null
compdef a=sudo
compdef s=sudo
compdef t=tmux
compdef glue=ssh

alias j='ssh -J stowe.umd.edu'
compdef j=ssh

# Easy way to switch to project
p() {
    cd "${HOME}/projects/${1}" && ls
}
compdef "_files -W ${HOME}/projects" p

# Set standard umask
if [[ $OS == 'Windows_NT' ]]; then
    umask 002
else
    umask 022
fi

# Glue polutes my shell
# (for some reason these have to go here, not .zshenv)
unset LESS LESSOPEN

# vim:ft=zsh
