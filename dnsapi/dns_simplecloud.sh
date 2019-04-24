#!/usr/bin/env sh

#Author: Alexander Fadeev <otakuf@gmail.com>

SIMPLECLOUD_API_URL="https://api.simplecloud.ru/v3/domains"

########  Public functions #####################

#Usage: dns_simplecloud_add   _acme-challenge.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_simplecloud_add() {
  fulldomain="${1}"
  txtvalue="${2}"

  if ! _Simplecloud_API; then
    return 1
  fi

  _info "Using Simplecloud API"
  _debug ""
  _debug ""
  _debug "Calling: dns_simplecloud_add() '${fulldomain}' '${txtvalue}'"
  _debug ""
  _debug ""

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _payload="{
              \"type\": \"TXT\",
              \"name\": \"$_sub_domain\",
              \"data\": \"$txtvalue\"
            }"

  if _rest POST "/$_domain_id/records" "$_payload" && [ -n "$response" ]; then
    _resource_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"\s*[0-9]+\"" | cut -d : -f 2 | tr -d " " | _head_n 1 | tr -d "\"")
    _debug _resource_id "$_resource_id"

    if [ -z "$_resource_id" ]; then
      _err "Error adding the domain resource."
      return 1
    fi

    _info "Domain resource successfully added."
    return 0
  fi

  return 1
}

#Usage: dns_simplecloud_rm   _acme-challenge.www.domain.com
dns_simplecloud_rm() {
  fulldomain="${1}"

  if ! _Simplecloud_API; then
    return 1
  fi

  _info "Using Simplecloud API"
  _debug "Calling: dns_simplecloud_rm() '${fulldomain}'"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if _rest GET "/$_domain_id/records" && [ -n "$response" ]; then
    response="$(echo "$response" | tr -d "\n" | tr '{' "|" | sed 's/|/&{/g' | tr "|" "\n")"

    resource="$(echo "$response" | _egrep_o "{.*\"name\":\s*\"$_sub_domain\".*}")"
    if [ "$resource" ]; then
      _resource_id=$(printf "%s\n" "$resource" | _egrep_o "\"id\":\"\s*[0-9]+\"" | _head_n 1 | cut -d : -f 2 | tr -d \ | tr -d "\"")
      if [ "$_resource_id" ]; then
        _debug _resource_id "$_resource_id"

        if _rest DELETE "/$_domain_id/records/$_resource_id" && [ -n "$response" ]; then
          # On 200/OK, empty set is returned. Check for error, if any.
          _error_response=$(printf "%s\n" "$response" | _egrep_o "\"errors\"" | cut -d : -f 2 | tr -d " " | _head_n 1)

          if [ -n "$_error_response" ]; then
            _err "Error deleting the domain resource: $_error_response"
            return 1
          fi

          _info "Domain resource successfully deleted."
          return 0
        fi
      fi

      return 1
    fi

    return 0
  fi

  return 1
}

####################  Private functions below ##################################

_Simplecloud_API() {
  if [ -z "$SIMPLECLOUD_API_KEY" ]; then
    SIMPLECLOUD_API_KEY=""

    _err "You didn't specify the Simplecloud API key yet."
    _err "Please create your key and try again."

    return 1
  fi

  _saveaccountconf SIMPLECLOUD_API_KEY "$SIMPLECLOUD_API_KEY"
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=12345
_get_root() {
  domain=$1
  i=2
  p=1

  if _rest GET; then
    response="$(echo "$response" | tr -d "\n" | tr '{' "|" | sed 's/|/&{/g' | tr "|" "\n")"

    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      hostedzone="$(echo "$response" | _egrep_o "{.*\"name\":\"$h\".*}")"
      if [ "$hostedzone" ]; then
        _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "\"id\":\"\s*[0-9]+\"" | _head_n 1 | cut -d : -f 2 | tr -d \ | tr -d "\"")
        _debug "$_domain_id"
        if [ "$_domain_id" ]; then
          _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
          _domain=$h
          return 0
        fi
        return 1
      fi

      p=$i
      i=$(_math "$i" + 1)
    done
  fi
  return 1
}

#method method action data
_rest() {
  mtd="$1"
  ep="$2"
  data="$3"

  _debug mtd "$mtd"
  _debug ep "$ep"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: Bearer $SIMPLECLOUD_API_KEY"

  if [ "$mtd" != "GET" ]; then
    # both POST and DELETE.
    _debug data "$data"
    response="$(_post "$data" "$SIMPLECLOUD_API_URL$ep" "" "$mtd")"
  else
    response="$(_get "$SIMPLECLOUD_API_URL$ep$data")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
