#!/Users/fgtrjhyu/homebrew/bin/bash

json() {
	cat<<-EOF
	{
		"kids": [
			{ "arg": "a" }
		, { "arg": "b" }
		, { "arg": "c" }
		, { "arg": "d" }
		, { "arg": "e" }
		]
	}
	EOF
}

procdelim() {
	[[ $procind -gt 0 ]] && echo -n ","
}
 
procresult() {
	cat<<-JSON
  {
		"procind": ${procind:-null},
		"procitems": ${procitems:-null},
		"id-${procind:-null}": "key-${procind:-null}",
		"arg_${procind:-null}": "${PROCVARS[source_kids_${procind}_arg]}",
		"array": [
			{
				"key": ${procind:-null},
				"value": "value-${procind:-null}"
			}
		],
		"object": {
			"key-${procind-null}": "value-${procind-null}"
		}
	}
	JSON
}

procinit() {
	echo "procinit:$procitems"
}

procend() {
	echo "procend:$procitems:$?"
}

procitem() {
	echo "procitem:$procind of $procitems"
	echo "$(procdelim)$(procresult)" >&5
  [[ -n "${DIE}" && $procind -eq "${DIE}" ]] && exit 1
}

jqlib() {
	cat<<-'JQ'
	def join(delim):
		reduce .[] as $e (""; if . == "" then $e else . + delim + $e end)
	;
  def mkproc(len):
		{ "com": "procitems=\(len) procind=\(.key) procitem", "fd": .value.fd }
  ;
	def nesting(a):
		length as $len |
		to_entries | map(mkproc($len)) | reduce .[] as $e (a; "((\($e.com) 1>&3) 5>&1) | ((\(.)) \($e.fd)<&0)")
	;
	def multicat:
		map("$(cat 0<&\(.fd))") | join("") | "echo \"[\(.)]\">&5"
  ;
	def parallel:
		to_entries | map({"fd": (.key + 6), "origin": .value}) as $list | $list | nesting($list | multicat)
	;
	def sequence:
		length as $len |
		[range(0;$len)] | map(@text) | join(" ") |
		"(((procitems=\($len); procinit; (for procind in \(.);do procitem; done); procend) 1>&3) 5>&1) | echo \"[$(cat)]\">&5"
	;
  def processor(parallel_processing):
		if parallel_processing then
			parallel
		else
			sequence
		end
	;
	def defvar(prefix):
		type as $type |
			if $type == "object"then
				to_entries | map(select(.value!=null)) | map(
					(prefix + [.key]) as $name | .value | defvar($name) | .[]
				) 
			elif $type == "array" then
				to_entries | map(select(.value!=null)) | map(
					(prefix + [.key]) as $name | .value | defvar($name) | .[]
				)
			else
				[ { "key": prefix, "value":. } ]
			end
	;

	def defvar:
		["unset PROCVARS"] + 
		["declare -A PROCVARS"] + 
		(defvar([]) | map(. as $e | $e.key | map(@text) | join("_") | "PROCVARS[\(.)]=\($e.value | @sh)")) | map("\(.);\n") | join("")
	;

	def is_entry_form(a):
		((a | length) == 1) and (a[0] | keys | reduce .[] as $e(true; . and $e == "key" or $e == "value"))
	;
	def unique_keys(a;b):
		reduce (a,b) as $e([]; . + ($e | keys)) | unique
	;
	def select(orig;other):
		map(. as $key | { "key": $key, "orig": orig[$key], "other": other[$key] })
	;
	def entry_to_array(a):
		if is_entry_form(a) then
			a[0] as $e | [range(0;$e.key + 1)] | reduce .[] as $i([];. + (if ($i == $e.key) then [$e.value] else [null] end))
		else
			a
		end
	;
	def merges(other):
		if . == null then
			if (other | type) == "array" then
				entry_to_array(other)
			else
				other
			end
		elif other == null then
			.
		else
			(. | type) as $t |
			(other | type) as $u |
			if $t == $u then
				if $t == "object" then
					. as $orig |unique_keys($orig;other) | select($orig;other) | map(. as $e | { "key": $e.key, "value": ($e.orig | merges($e.other)) }) | from_entries
				elif $t == "array" then
					. as $orig | entry_to_array(other) as $other | unique_keys($orig;$other) | map(. as $index | ($other[$index] | merges($orig[$index])))
				else
					other
				end
			else
				other
			end
		end
	;
	def select_processor:
		.parallel_processing as $parallel_processing | .source.kids | processor($parallel_processing)
	;
	def string_script:
		[defvar, select_processor] | join("")
	;
	def object_join(o):
		reduce .[] as $e(o; merges($e))
	;
	JQ
}

jq_object_combined() {
	cat<<-EOF 
		$(jqlib)
		object_join($(orig))
	EOF
}

jq_string_script() {
	cat<<-EOF
		$(jqlib)
		. | string_script
	EOF
}

jq_string_script_defvar() {
	cat<<-EOF
		$(jqlib)
		. | defvar
	EOF
}

config() {
	cat<<-JQ
	{
		"parallel_processing": ${PARALLEL_PROCESSING:-false},
		"source": $(cat)
	}
	JQ
}

runcom() {
	set -v
	(jq -r "$(jq_string_script)" | (eval "$(cat)" 1>&3) 5>&1) | jq -r "$(jq_object_combined)"
}

defvar() {
	set -v
	jq -r "$(jq_string_script_defvar)" | eval "$(cat)"
}

orig() {
	cat<<-EOF
	{
		"origin": "this is origin"
	}
	EOF
}

((json | config | runcom) 3>&1)
