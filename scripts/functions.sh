log()        { echo "[log]  $*"; }
info()       { echo "[info] $*"; }
warn()       { echo "[warn] $*"; }
error()      { echo "[error] $*"; exit 1; }

contains() {
  local needle=${1,,}; shift || return 1
  local s; for s in "$@"; do [[ ${s,,} == "$needle" ]] && return 0; done
  return 1
}

is_running() { docker ps --filter "name=^$1\$" --format '{{.Names}}' | grep -q "^$1\$"; }

dedent() {
  awk 'BEGIN{m=-1;n=0} {l=$0; if(l~/[^[:space:]]/){match(l,/^[[:space:]]*/);i=RLENGTH; if(m==-1||i<m)m=i} a[n++]=l}
       END{for(i=0;i<n;i++){l=a[i]; if(l~/^[[:space:]]*$/)print ""; else print substr(l,m+1)}}'
}

write() {
  local fileName="$1"
  local dirName; dirName="$(dirname "$fileName")"
  local content="$2"
  mkdir -p "$dirName"
  printf "%s" "$content" | dedent >"$fileName"
}

append() {
  local fileName="$1"
  local dirName; dirName="$(dirname "$fileName")"
  local content="$2"
  mkdir -p "$dirName"
  printf "%s" "$content" | dedent >>"$fileName"
}

sudo_write()  { local f="$1" c="$2"; sudo bash -c "$(declare -f dedent); printf %s \"$c\" | dedent >\"$f\""; }
sudo_append() { local f="$1" c="$2"; sudo bash -c "$(declare -f dedent); printf %s \"$c\" | dedent >>\"$f\""; }