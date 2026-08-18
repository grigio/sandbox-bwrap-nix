export EDITOR=micro
export PAGER=less
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export USER=nixuser
export SHELL="$(command -v bash)"

# Keep the terminal identity bwrap injected (TERM=xterm-ghostty, TERM_PROGRAM=ghostty)
# so TUIs like jcode can detect kitty-graphics inline-image support. Only fall back
# to a bare xterm when TERM wasn't set at all.
export TERM="${TERM:-xterm-256color}"
if [ -z "${TERM_PROGRAM:-}" ]; then
  case "$TERM" in
    *ghostty*) export TERM_PROGRAM=ghostty ;;
  esac
fi

export JCODE_NO_AUTO_UPDATE=1


if [ -n "$BASH_VERSION" ] && type complete &>/dev/null; then
  for _bc in /nix/store/*bash-completion*/share/bash-completion/bash_completion; do
    [ -f "$_bc" ] && . "$_bc" && break
  done
  unset _bc
fi

git_branch() {
  git branch --show-current 2>/dev/null && return
  git rev-parse --short HEAD 2>/dev/null && return
}

case "$TERM" in
  dumb|"")
    PS1='\u@\h \W \$ '
    ;;
  *)
    PS1='\e[1;31m●\e[0m \e[1;34m\W\e[0m\e[1;33m$(git_branch | sed "s/.*/ (&)/")\e[0m \$ '
    ;;
esac

alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
