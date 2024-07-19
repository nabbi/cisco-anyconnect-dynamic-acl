#!/bin/sh
# the next line restarts using tclsh \
exec tclsh "$0" "$@"
# nic@boet.cc

set info 1
set debug 0
set trace 0

set path [file dirname [file normalize [info script]]]

source $path/inc/common.tcl

if { [catch { source $path/inc/config.tcl }] } {
    puts "config.tcl does not exist, please create it from config.tcl.example"
    exit 1
}

proc help {} {
	puts "Cisco ASA AnyConnect -- configures ACL for split-tunnel exclusion (ie bypassed networks)"
	puts "Usage:    $::argv0"
	exit 64
}

if {[llength $argv] != 0} {
	puts "Incorrect number of arguments"
	[help]
}

# Read the dynamic input list
if { ! [catch { set input [open $path/lists/dynamic.txt r] }] } {
    append networks [split [read $input] "\n"] "\n"
    close $input
} else {
    puts "lists/dynamic.txt does not exist, please conjour one with magic."
    exit 1
}

# Static manaul network lists
if { ! [catch { set input [open $path/lists/static.txt r] }] } {
    append networks [split [read $input] "\n"] "\n"
    close $input
}

# confirm we have a list to process before continuing
if { [llength $networks] < 1 } {
    puts "did not read any CIDRs, aborting"
    exit 1
}

# Exclusions from networks list
# These values must match exactly how they appear within the dynamic input list
# This is in no way granular route filtering
if { ! [catch { set input [open $path/lists/exclude.txt r] }] } {
    set exclude [split [read $input] "\n"] 
    close $input
} else {
    set exclude {}
}

# process the network lists and compile the ACL changes to be made
foreach net [lsort -unique $networks] {

    # ignore comments and blank lines
    if { [string index $net 0] == "#" || [string index $net 0] == " " || [string length $net] == 0 } { continue }

    # exclude - ignore networks if exact matched
    set x [lsearch $exclude $net]
    if { $x != -1 } {
        if {$debug} { puts "# excluding: $net" }
        continue
    }

    # returns {net mask} {type}
    # invalid inputs are filtered by function and wont be added to acl as the ipv4 type is missing
    set nm [netmask $net]
    
    if { [lindex $nm 1] == "ipv4" } {
        lappend acl_new "access-list ${config(acl_name)} extended permit ip [lindex $nm 0] any4"
    }
    if { [lindex $nm 1] == "ipv6" } {
        lappend acl_new "access-list ${config(acl_name)} extended permit ip [lindex $nm 0] any6"
    }

}

# next, loop through each asa host
foreach h $config(hosts) {
	puts "# $h: running"

    # read from device the current acl statements
    # this will fail with error if access-list does not exist
    set cmds "show running-config access-list $config(acl_name)\n"
    if { [catch {set running_config [myexec $path/exp/asa-cli.exp $h << $cmds] } results options] } {
        log "error" "$h failure, skipping"
        continue
    }
    #set results [myexec $path/exp/asa-cli.exp $h << $cmds]
    ## set results "access-list $config(acl_name) remark 'test'" 
    ## if { $debug } { puts "##cmd result: $results"}

    
    # initialize an empty old acl var
    set acl_old {}

    # read the config output and parse buffer into vars
	foreach line [split $running_config "\n"] {
		switch -glob -- $line {
			"access-list *" {
                if { [lindex $line 3] == "permit" } {
                    # store the existing acl permit statements
                    lappend acl_old [string trim $line]

                } elseif { [lindex $line 2] == "remark" } {
                    # validates to confirm we got an ACL, even an empty one
                    # we do this additional check to confirm we have real data
                    if { $trace } { puts "## ACL ## $line" }
                    set acl_remark 1
                }
            }
            default {
                # ignore other lines in the results buffer
                continue
            }
		}
	}

    if { ! ([info exists acl_remark]) } {
        # this logic might never match becase the expect ssh script will fail with "does not exist"
        # sanity check confirms we processed acl data above so keeping it
        puts "skipping $h -- configuration not prepared for managing the split-tunnel ACL"
        continue
    }
    unset acl_remark

    # compare what acl line changes are needed
    # cisco asa converts our previously entered values to condensed values
    # resulting in "same" lines being deleted and readded
    # so make sure input lists match
    #
    # 1.2.3.4 255.255.255.255 > host 1.2.3.4
    # 2620:1ec:900:0:0:0:0:0/46 > 2620:1ec:900::/46

    set acl_merge {}

    # check if there are new acl lines to be added
    foreach n $acl_new {

        set x [lsearch $acl_old $n ]
        if { $x == -1 } {
            if {$info} { puts "#  add: [lindex $n 5] [lindex $n 6]" }
            log "info" "$h add [lindex $n 5] [lindex $n 6]"
            lappend acl_merge $n
        }
    }
 
    # check if any old acl lines need to be removed
    foreach o $acl_old {

        set x [lsearch $acl_new $o ]
        if { $x == -1 } {
            if {$info} { puts "#  rem: [lindex $o 5] [lindex $o 6]" }
            log "info" "$h rem [lindex $o 5] [lindex $o 6]"
            lappend acl_merge "no $o"
        } 
    }

    if { [llength $acl_merge] > 0 } {
        ## compile commands to process
        set cmds "configure terminal\n"
        
        append cmds [join $acl_merge "\n"]
        append cmds "\n"
        
        append cmds "end\n"
        # this is my special command to trigger asa-cli.exp to process the copy run sta correctly
        append cmds ":save:\n"

        if {$trace} { puts $cmds }

        set config_results [myexec $path/exp/asa-cli.exp $h << $cmds]
	    if {$info} { puts "#  changes applied" }

    } else {
        if {$info} { puts "#  skipped no changes needed" }
    }
}

exit
