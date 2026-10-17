#!/bin/env tclsh
encoding system utf-8
package require debug.tcl

namespace eval ::debug {

# various scopes 
#
proc thread {args} {
	package require thread

	set thread [::thread::create -preserved]
	set scope [list ::thread::send $thread]
	ensemble inject show $scope
	tclsh $scope {*}$args
	::thread::release
}

proc trusted {{name {}} args} {
	if {$name eq ""} {
		set interp [interp create]
	} {
		if {[catch {interp issafe $name} safe]} {
			set interp [interp create $name]
		} elseif {$safe} {
			return -code error "not a trusted interpreter"
		}
		set interp $name
	}
	set scope [list interp eval $interp]
	if {$name eq ""} {
		ensemble inject show $scope
	}
	tclsh $scope {*}$args
	if {$name eq ""} {
		interp delete $interp
	} {
		set interp
	}
}

proc safe {{name {}} args} {
	if {$name eq ""} {
		set interp [interp create -safe]
		interp expose $interp tcl:info:cmdtype
		interp eval $interp {
			rename ::tcl::info::cmdtype {}
			rename tcl:info:cmdtype ::tcl::info::cmdtype
		}
	} {
		set interp $name
		if {[catch {interp issafe $interp} safe]} {
			::safe::interpCreate $interp
		} {
			if {!$safe} {
				return -code error "not a safe interpreter"
			}
		}
	}
	set scope [list interp eval $interp]
	if {$name eq ""} {
		ensemble inject show $scope
	}
	tclsh $scope {*}$args
	if {$name eq ""} {
		interp delete $interp
	} {
		set name
	}
}

proc ns {ns args} {
	set scope [list namespace eval $ns]
	tclsh $scope {*}$args
}

namespace export tclsh thread trusted safe ns

}

if {$::tcl_interactive} {
	namespace import ::debug::*
	return "debug loaded"
}

apply {{} {
	tclsh {uplevel 1} [apply {{} {
		set start {}
		while {[llength $::argv] > 0} {
			set ::argv [lassign $::argv source]
			incr ::argc -1
			if {$source eq "--"} break
			switch -glob $source {
			-e*	{
					if {[string length $source] > 2} {
						lappend start [string range $source 2 end]
					} elseif {$::argc > 0} {
						set ::argv [lassign $::argv source]
						incr ::argc -1
						lappend start $source
					}
				}
			default	{
					lappend start [list puts $source]
					lappend start [list uplevel #0\
						source $source]
				}
			}
		}

		join $start \n
	}}]
} ::debug}
