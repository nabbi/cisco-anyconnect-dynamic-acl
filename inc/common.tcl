# shorthand our logger
proc log {level msg} {
    puts "# logger # $level $msg"
    exec logger -p user.${level} "[info script] ${msg}"
}

## exit if child proccess fails, otherwise return result
proc myexec {args} {
    set status 0
    if {[catch {exec {*}$args} results options]} {
        set details [dict get $options -errorcode]
        if {[lindex $details 0] eq "CHILDSTATUS"} {
            set status [lindex $details 2]
        } else {
            # Some other error; regenerate it to let caller handle
            ## return -options $options -level 0 $results
            set status 70
        }
    }

    if { $status } {
        # this isn't quite right, prints and return the resulting error
        set msg "exit error $status $results"
        log "error" $msg
        return -code error --errorinfo $results --errorcode $status
    }
    return $results
}

# KISS use an ip calculator to normalize the input
# returns appropriate formatting for cisco asa acl
proc netmask {cidr} {

	set sipcalc [myexec sipcalc $cidr]

	foreach line [split $sipcalc "\n"] {

        switch -glob -- $line {
            "Network address*" {
                #ipv4 
                set ipv4 [lindex $line 3]
                continue
            }
            "Network mask*" {
                # ipv4
                set ipv4mask [lindex $line 3]
                # we break here to avoid matching again on subsequent mask lines from sipcalc
                break
            }
            "Compressed address*" {
                # ipv6
                set ipv6 [lindex $line 3]
            }
            "Prefix length*" {
                # ipv6
                set ipv6prefix [lindex $line 3]
            }

            default {}
        }
	}

    if { [info exists ipv4] && [info exists ipv4mask] } {
        # return host formatted entry
        if { [string match $ipv4mask "255.255.255.255"] } {
            return [list "host $ipv4" "ipv4"]
        } else {
            return [list "$ipv4 $ipv4mask" "ipv4"]
        }

    } elseif { [info exists ipv6] && [info exists ipv6prefix] } {
        # return host formatted entry
        if { [string match $ipv6prefix "128"] } {
            return [list "host $ipv6" "ipv6"]
        } else {
            return [list "$ipv6/$ipv6prefix" "ipv6"]
        }
    } else {
        # this will trigger the caller skip this entry if we got bad info
        return -code continue 
    }
}
