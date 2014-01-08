# Based on prompt-disambiguate.zsh from
# https://github.com/Valodim/zsh-prompt-powerline/blob/master/hooks/prompt-disambiguate.zsh
#
# original disambiguate by Mikachu

# usage of disambiguate:
# disambiguate /usr/share/zsh/function ; echo $REPLY
# -> /u/sh/zs/f
# disambiguate -k /usr/share/zsh/function ; echo $REPLY
# -> /u/sh/zs/function
# disambiguate -k zsh/function /usr/share/ ; echo $REPLY
# -> zs/function


disambiguate () {

    # for compatibility
    setopt localoptions noksharrays

    # this is a modification of Mikachu's disambiguate-keeplast, adding support
    # for an argument to use instead of PWD, and a second argument which is
    # used as a prefix for globbing, but is not part of the disambiguated path.
    # it also supports the -k parameter to keep the last part intact (rather
    # than using a second function for this behavior)

    local short full part cur
    local first
    local -a split # the array we loop over

    # need to do it this way
    local treatlast=1
    if [[ $1 == '-k' ]]; then
        treatlast=
        shift
    fi

    1=${1:-$PWD}
    local prefix=$2

    if [[ $1 == / ]]; then
        REPLY=/
        return 0
    fi

    # We do the (D) expansion right here and
    # handle it later if it had any effect
    split=(${(s:/:)${(Q)${(D)1:-$1}}})

    # Handling. Perhaps NOT use (D) above and check after shortening?
    if [[ -z $prefix && $split[1] = \~* ]]; then
      # named directory we skip shortening the first element
      # and manually prepend the first element to the return value
      first=$split[1]
      # full should already contain the first
      # component since we don't start there
      full=$~split[1]
      shift split
    fi

    # we don't want to end up with something like ~/
    if [[ -z $prefix ]] && (( $#split > 0 )); then
        part=/
    fi

    # loop over all but the last, plus the last if keeplast is zero
    for cur in $split[1,-2] ${treatlast:+$split[-1]}; {
        while {
            part+=$cur[1]
            cur=$cur[2,-1]
            local -a glob
            glob=( $prefix$full/$part*(-/N) )
            # continue adding if more than one directory matches or
            # the current string is . or ..
            # but stop if there are no more characters to add
            (( $#glob > 1 )) || [[ $part == (.|..) ]] && (( $#cur > 0 ))
        } { # this is a do-while loop
    }
      full+=$part$cur
      short+=$part
      part=/
    }

    # piece them together
    REPLY=$first$short
    # if we skipped the last, add it unaltered
    (( ! treatlast )) && REPLY+=$part$split[-1]

    return 0

}
