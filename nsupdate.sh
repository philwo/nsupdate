#!/bin/bash

# Update a nameserver entry at inwx with the current WAN IP (DynDNS)

# Copyright 2013 Christian Busch
# http://github.com/chrisb86/

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Check required tools.
command -v curl &> /dev/null || { echo >&2 "I require curl but it's not installed. Note: all needed items are listed in the README.md file."; exit 1; }
command -v awk &> /dev/null || { echo >&2 "I require awk but it's not installed. Note: all needed items are listed in the README.md file."; exit 1; }
command -v drill &> /dev/null || command -v nslookup &> /dev/null || { echo >&2 "I need drill or nslookup installed. Note: all needed items are listed in the README.md file."; exit 1; }

silent="NO"
failed_updates="0"
ip_check_site="https://ifconfig.co/ip"
use_drill="NO"

verbose() {
   if [[ "$silent" == "NO" ]]; then
      echo "$1"
   fi
}

# Check if there are any usable config files.
if ls "$(dirname "$0")"/nsupdate.d/*.config &> /dev/null; then
   # Loop through configs.
   for f in "$(dirname "$0")"/nsupdate.d/*.config; do
      source "$f"

      ## Set record type to IPv4.
      verbose "Starting nameserver update with config file $f"

      ## Set record type to IPv6.
      if [[ "$IPV6" == "YES" ]]; then
         record_type="AAAA"
         wan_ip="$(ip -j route get 2001:4860:4860::8888 | jq -r '.[0].prefsrc')"
      else
         record_type="A"
         wan_ip="$(curl --fail --silent -4 "$ip_check_site")"
      fi

      if [[ "$use_drill" == "YES" ]]; then
         nslookup=$(drill "$DOMAIN" @ns.inwx.de $record_type | head -7 | tail -1 | awk '{print $5}')
      else
         nslookup=$(nslookup -sil -type=$record_type "$DOMAIN" - ns.inwx.de | tail -2 | head -1 | rev | cut -f1 -d' ' | rev)
      fi

      api_xml="<?xml version=\"1.0\"?>
      <methodCall>
         <methodName>nameserver.updateRecord</methodName>
         <params>
            <param>
               <value>
                  <struct>
                     <member>
                        <name>user</name>
                        <value>
                           <string>$INWX_USER</string>
                        </value>
                     </member>
                     <member>
                        <name>pass</name>
                        <value>
                           <string>$INWX_PASS</string>
                        </value>
                     </member>
                     <member>
                        <name>id</name>
                        <value>
                           <int>$INWX_DOMAIN_ID</int>
                        </value>
                     </member>
                     <member>
                        <name>content</name>
                        <value>
                           <string>$wan_ip</string>
                        </value>
                     </member>
                  </struct>
               </value>
            </param>
         </params>
      </methodCall>"

      if [[ "$nslookup" != "$wan_ip" ]]; then
         xml="$(curl --fail \
                     --silent \
                     --request POST \
                     --header 'Content-Type: application/xml' \
                     --data "$api_xml" \
                     https://api.domrobot.com/xmlrpc/)"
         exit_status=$?

         if [[ "$exit_status" == "0" && "$xml" == *'<name>code</name><value><int>1000</int>'* ]]; then
            verbose "$DOMAIN updated. Old IP: $nslookup New IP: $wan_ip"
         else
            verbose "$DOMAIN update failed, curl exit status $exit_status with XML: $xml"
            failed_updates=$((failed_updates + 1))
         fi
      else
         verbose "No update needed for $DOMAIN. Current IP: $nslookup"
      fi

      unset api_xml
      unset nslookup
      unset wan_ip

      unset IPV6
      unset INWX_USER
      unset INWX_PASS
      unset DOMAIN
      unset INWX_DOMAIN_ID
   done
else
   verbose "There does not seem to be any config file available in $(dirname "$0")/nsupdate.d/."
   exit 1
fi

if [[ $failed_updates -gt 0 ]]; then
   verbose "$failed_updates updates failed"
fi

exit $failed_updates
