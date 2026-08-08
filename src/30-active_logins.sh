# --------------------- 30-active_logins.sh ---------------------
# This file contains functions to retrieve and display active logins.

ACTIVE_LOGINS_LIST=""

# who's default output is a stable, standardized format shared by GNU
# coreutils/util-linux/BSD: "user  line  date/time  (origin)", origin
# being optional and either an IP, a hostname, or a display like ":0".
# The date/time formatting itself is NOT stable though — e.g. on this
# system it's "2026-07-27 07:48" normally but "Jul 27 07:48" (no year)
# under LC_ALL=C, so don't force a locale here, and don't match a fixed
# date pattern either: just take everything between the terminal field
# and the optional trailing "(origin)" as the datetime, whatever shape
# it comes in.
get_active_logins() {
  if [ -n "$ACTIVE_LOGINS_LIST" ]; then
    return 0
  fi

  if ! command -v who >/dev/null 2>&1; then
    return 0
  fi

  _raw=$(who 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  ACTIVE_LOGINS_LIST=$(printf '%s\n' "$_raw" | awk '
    {
      if ($1 == "") next

      origin = "-"
      if (match($0, /\([^)]*\)/)) {
        origin = substr($0, RSTART + 1, RLENGTH - 2)
      }

      body = $0
      sub(/\([^)]*\).*$/, "", body)
      gsub(/[[:space:]]+$/, "", body)

      n = split(body, tok, /[[:space:]]+/)
      extra = n - 1
      if (min_extra == 0 || extra < min_extra) min_extra = extra

      users[NR] = tok[1]
      origins[NR] = origin
      ntoks[NR] = n
      extras[NR] = extra
      for (i = 2; i <= n; i++) toks[NR, i] = tok[i]
    }
    END {
      # The date/time token count stays constant across a single `who`
      # run (same locale, same command), so bootstrap it from whichever
      # row has the fewest extra tokens -- that must be a row with a
      # plain one-token terminal (pts/0, tty1, seat0, etc). Any row with
      # more extra tokens than that baseline has a multi-token terminal
      # instead of a wider date (seen in the wild: some sshd setups
      # record a compound line like "sshd pts/4"), so the surplus folds
      # into the terminal instead of leaking into the date/time column.
      date_tokens = min_extra - 1
      if (date_tokens < 1) date_tokens = 1

      for (r = 1; r <= NR; r++) {
        if (!(r in ntoks)) continue

        term_count = extras[r] - date_tokens
        if (term_count < 1) term_count = 1

        term = ""
        for (i = 2; i <= 1 + term_count; i++) {
          term = (term == "" ? toks[r, i] : term " " toks[r, i])
        }

        dt = ""
        for (i = 2 + term_count; i <= ntoks[r]; i++) {
          dt = (dt == "" ? toks[r, i] : dt " " toks[r, i])
        }

        print users[r] "|" term "|" dt "|" origins[r]
      }
    }')

  return 0
}

print_active_logins() {
  get_active_logins

  if [ -z "$ACTIVE_LOGINS_LIST" ]; then
    return 0
  fi

  # Dynamic per-column width (like the Services grid) instead of guessed
  # fixed widths, seeded with the header labels' own lengths so a short
  # column still fits its header.
  _widths=$(printf '%s\n' "$ACTIVE_LOGINS_LIST" | awk -F'|' '
    BEGIN { w1 = 4; w2 = 8; w3 = 13; w4 = 4 }
    {
      if (length($1) > w1) w1 = length($1)
      if (length($2) > w2) w2 = length($2)
      if (length($3) > w3) w3 = length($3)
      if (length($4) > w4) w4 = length($4)
    }
    END { print w1, w2, w3, w4 }')

  IFS=' ' read -r _w1 _w2 _w3 _w4 <<EOF
$_widths
EOF

  printf "%bActive Logins:\n" "$W"
  printf "%b  %-*s | %-*s | %-*s | %s\n" "$W" "$_w1" "User" "$_w2" "Terminal" "$_w3" "Session Start" "From"

  while IFS='|' read -r _user _term _dt _origin; do
    [ -z "$_user" ] && continue
    printf "  %-*s | %-*s | %-*s | %s\n" "$_w1" "$_user" "$_w2" "$_term" "$_w3" "$_dt" "$_origin"
  done <<EOF
$ACTIVE_LOGINS_LIST
EOF
  if [ "$1" = "1" ]; then
    printf "\n"
  fi
}
