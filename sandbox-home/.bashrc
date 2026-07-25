export EDITOR=micro
export PAGER=less
export LANG=C
export LC_ALL=C
export TERM=xterm-256color
export USER=nixuser

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