package require ensemble-builder

namespace eval ::debug {

#
# pkg_mkIndex prevents creation of the namespace in the imported package
# which makes namespace import fail, so ignore it if it doesn't exist
#
if {[namespace ensemble exists ::ensemble::ensemble]} {
	namespace import ::ensemble::ensemble
}

# define the various parts for the show ensemble

ensemble part show proc {name} {
	set qp [uplevel [list namespace which -command $name]]
	if {$qp eq ""} {return -code error "$name not found"}
	set qp [namespace origin $name]

	set args [lmap arg [info args $qp] {
		if {[info default $qp $arg default]} {
			list $arg $default
		} {
			list $arg
		}
	}]

	list proc $qp $args [info body $qp]
}

ensemble part show cmds {{ns {}} {pattern *}} {
#
# info cmdtype doesn't work in a safe interpreter, so we
# catch some cases using other methods.  skipping coroutines,
# object-related stuff, alias (could do interp alias but the
# command can be renamed, which would then mask something else
# in the same place.  anything unrecognized is reported as native
#
# note: ::tcl:info:cmdtype is a hidden command, exposing it,
# removing ::tcl::info::cmdtype, and renaming to that, will
# restore the info cmdtype subcommand, but this is still useful
# if that hasn't been done
#
# this also adds a reference to the origin on an import
#
const cmdtype {cmd {
	set qc [uplevel namespace which -command $cmd]
	set oc [uplevel namespace origin $cmd]

	if {[catch {info cmdtype $oc} out] != 0} {
		if {[namespace ensemble exists $oc]} {
			set out ensemble
		} elseif {[interp exists $oc]} {
			set out interp
		} elseif {[catch {info body $oc}] == 0} {
			set out proc
		} else {
			set out native
		}
	}

	string cat [if {$qc ne $oc} {
		string cat import --> $oc -->
	}] $out
}}

	if {$ns eq {}} {
		set ns [uplevel namespace current]
	}
	join [lmap cmd [lsort [info commands ${ns}::${pattern}]] {
		set type [apply $cmdtype $cmd]
		list $cmd $type
	}] \n
}

ensemble part show vars {{ns {}}} {
	if {$ns eq {}} {
		set ns [uplevel namespace current]
	}
	join [lmap var [lsort [uplevel info vars ${ns}::*]] {
		string range [if {[info constant $var]} {
			list $var :const: [set $var]
		} elseif {[array exists $var]} {
			list $var :array: [array get $var]
		} elseif {[info exists $var]} {
			list $var : [set $var]
		} else {
			list $var undefined
		}] 0 200
	}] \n
}

ensemble map show representation ::tcl::unsupported::representation

ensemble part show ns {{ns {::}}} {
	join [concat $ns [lmap ns [lsort [namespace children $ns]] {show ns $ns}]] \n
}


#
#
proc debug {label cmd args} {
	puts "debug $label: $cmd $args"
	set r [uplevel 1 $cmd $args]
	puts "debug $label= [list $r]"
	set r
}

#
# now create the ensembles and clean up
#

ensemble build

proc tclsh {{scope {uplevel 1}} {script {}}} {
	global tcl_interactive
	set save $tcl_interactive
	set tcl_interactive 1

	set out ""
	set cmd ""
	set prompt true

	while {true} {
		if {$script ne "" && $out eq ""} {
			if {[regexp {\A *:(?!:) *(.*)?\Z} $script -> expr]} {
				if {[string is space $expr]} {
					set script [list {*}$scope ->]
				} else {
					set script [list -> $scope $expr]
				}
			} {
				set script [list {*}$scope $script]
			}

			set script [catch {{*}$script} result error]

			if {$script != 0} {
				set result [format "%s\ncode: %s" \
					$script [dict getdef $error -errorinfo [list $result]]]

				unset -nocomplain ::error
				array set ::error $error
			}

			if {$result ne ""} {set out "$result\n"}
			set script ""
			set prompt true
		}

		if {$prompt} {
			puts -nonewline "$out[expr {($cmd eq "") ? "> " : ""}]"
			flush stdout
			set out ""
			set prompt false
			continue
		}

		set prompt true

		vwait -readable stdin
		set eof [gets stdin new]
		if {$eof < 0} break
		if {$eof == 0} continue

		if {$cmd eq ""} {
			set cmd $new
		} {
			append cmd \n $new
		}

		if {[info complete ${cmd}\n]} {
			set script $cmd
			set cmd ""
		}
	}

	set tcl_interactive $save
	if {$tcl_interactive} {
		puts "leaving ..."
	}
}

proc -> {{scope eval} args} {
	if {[llength $args] != 0} {
		set input [concat {*}$args]
		set save [regexp {\A *([a-zA-Z0-9:()]+) *= *(.*)\Z}\
			$input -> var input]

		set save [expr {$save ? $var : "last"}]
		set eval [list uplevel 1 {*}$scope [
			list set $save \[expr \{${input}\}\]
		]]

		if {[catch $eval result]} {
			puts "error: $result"
		} {
			puts $result
		}
		return
	}

	while true {
		puts -nonewline "-> "
		flush stdout
		if {[gets stdin input] == -1} break
		if {[string is space $input]} continue
		-> {uplevel 1} $input
	}
}

namespace export tclsh show debug
}

package provide debug.tcl 1.0
