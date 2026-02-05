# Snapshot file
# Unset all aliases to avoid conflicts with functions
unalias -a 2>/dev/null || true
# Functions
compaudit () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
compdef () {
	local opt autol type func delete eval new i ret=0 cmd svc 
	local -a match mbegin mend
	emulate -L zsh
	setopt extendedglob
	if (( ! $# ))
	then
		print -u2 "$0: I need arguments"
		return 1
	fi
	while getopts "anpPkKde" opt
	do
		case "$opt" in
			(a) autol=yes  ;;
			(n) new=yes  ;;
			([pPkK]) if [[ -n "$type" ]]
				then
					print -u2 "$0: type already set to $type"
					return 1
				fi
				if [[ "$opt" = p ]]
				then
					type=pattern 
				elif [[ "$opt" = P ]]
				then
					type=postpattern 
				elif [[ "$opt" = K ]]
				then
					type=widgetkey 
				else
					type=key 
				fi ;;
			(d) delete=yes  ;;
			(e) eval=yes  ;;
		esac
	done
	shift OPTIND-1
	if (( ! $# ))
	then
		print -u2 "$0: I need arguments"
		return 1
	fi
	if [[ -z "$delete" ]]
	then
		if [[ -z "$eval" ]] && [[ "$1" = *\=* ]]
		then
			while (( $# ))
			do
				if [[ "$1" = *\=* ]]
				then
					cmd="${1%%\=*}" 
					svc="${1#*\=}" 
					func="$_comps[${_services[(r)$svc]:-$svc}]" 
					[[ -n ${_services[$svc]} ]] && svc=${_services[$svc]} 
					[[ -z "$func" ]] && func="${${_patcomps[(K)$svc][1]}:-${_postpatcomps[(K)$svc][1]}}" 
					if [[ -n "$func" ]]
					then
						_comps[$cmd]="$func" 
						_services[$cmd]="$svc" 
					else
						print -u2 "$0: unknown command or service: $svc"
						ret=1 
					fi
				else
					print -u2 "$0: invalid argument: $1"
					ret=1 
				fi
				shift
			done
			return ret
		fi
		func="$1" 
		[[ -n "$autol" ]] && autoload -rUz "$func"
		shift
		case "$type" in
			(widgetkey) while [[ -n $1 ]]
				do
					if [[ $# -lt 3 ]]
					then
						print -u2 "$0: compdef -K requires <widget> <comp-widget> <key>"
						return 1
					fi
					[[ $1 = _* ]] || 1="_$1" 
					[[ $2 = .* ]] || 2=".$2" 
					[[ $2 = .menu-select ]] && zmodload -i zsh/complist
					zle -C "$1" "$2" "$func"
					if [[ -n $new ]]
					then
						bindkey "$3" | IFS=$' \t' read -A opt
						[[ $opt[-1] = undefined-key ]] && bindkey "$3" "$1"
					else
						bindkey "$3" "$1"
					fi
					shift 3
				done ;;
			(key) if [[ $# -lt 2 ]]
				then
					print -u2 "$0: missing keys"
					return 1
				fi
				if [[ $1 = .* ]]
				then
					[[ $1 = .menu-select ]] && zmodload -i zsh/complist
					zle -C "$func" "$1" "$func"
				else
					[[ $1 = menu-select ]] && zmodload -i zsh/complist
					zle -C "$func" ".$1" "$func"
				fi
				shift
				for i
				do
					if [[ -n $new ]]
					then
						bindkey "$i" | IFS=$' \t' read -A opt
						[[ $opt[-1] = undefined-key ]] || continue
					fi
					bindkey "$i" "$func"
				done ;;
			(*) while (( $# ))
				do
					if [[ "$1" = -N ]]
					then
						type=normal 
					elif [[ "$1" = -p ]]
					then
						type=pattern 
					elif [[ "$1" = -P ]]
					then
						type=postpattern 
					else
						case "$type" in
							(pattern) if [[ $1 = (#b)(*)=(*) ]]
								then
									_patcomps[$match[1]]="=$match[2]=$func" 
								else
									_patcomps[$1]="$func" 
								fi ;;
							(postpattern) if [[ $1 = (#b)(*)=(*) ]]
								then
									_postpatcomps[$match[1]]="=$match[2]=$func" 
								else
									_postpatcomps[$1]="$func" 
								fi ;;
							(*) if [[ "$1" = *\=* ]]
								then
									cmd="${1%%\=*}" 
									svc=yes 
								else
									cmd="$1" 
									svc= 
								fi
								if [[ -z "$new" || -z "${_comps[$1]}" ]]
								then
									_comps[$cmd]="$func" 
									[[ -n "$svc" ]] && _services[$cmd]="${1#*\=}" 
								fi ;;
						esac
					fi
					shift
				done ;;
		esac
	else
		case "$type" in
			(pattern) unset "_patcomps[$^@]" ;;
			(postpattern) unset "_postpatcomps[$^@]" ;;
			(key) print -u2 "$0: cannot restore key bindings"
				return 1 ;;
			(*) unset "_comps[$^@]" ;;
		esac
	fi
}
compdump () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
compinit () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
compinstall () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
format-all () {
	echo "✨ Formatting all code..."
	if find . -name "*.py" | grep -q .
	then
		echo "Formatting Python files..."
		python3 -m black . 2> /dev/null || echo "⚠️  black not installed"
	fi
	if find . -name "*.sh" | grep -q .
	then
		echo "Formatting Shell scripts..."
		sh-format .
	fi
}
getent () {
	if [[ $1 = hosts ]]
	then
		sed 's/#.*//' /etc/$1 | grep -w $2
	elif [[ $2 = <-> ]]
	then
		grep ":$2:[^:]*$" /etc/$1
	else
		grep "^$2:" /etc/$1
	fi
}
lint-all () {
	echo "🔍 Linting all code..."
	if find . -name "*.py" | grep -q .
	then
		echo "Linting Python files..."
		python3 -m flake8 . 2> /dev/null || echo "⚠️  flake8 not installed"
	fi
	if find . -name "*.sh" | grep -q .
	then
		echo "Linting Shell scripts..."
		sh-check .
	fi
}
project-init () {
	local name="${1:-project}" 
	echo "🚀 Initializing Python/Shell project: $name"
	mkdir -p "$name"/{src,tests,scripts,docs}
	touch "$name/requirements.txt"
	touch "$name/setup.py"
	touch "$name/README.md"
	touch "$name/.gitignore"
	cat > "$name/scripts/setup.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "Setting up project..."
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
echo "✓ Setup complete"
SCRIPT
	chmod +x "$name/scripts/setup.sh"
	echo "✓ Project structure created: $name"
	find . -print | sed -e "s;[^/]*/;|____;g;s;____|; |;g" "$name" 2> /dev/null || ls -R "$name"
}
py-check () {
	echo "🐍 Python Environment Check"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Version: $(python3 --version)"
	echo "Location: $(which python3)"
	echo "Pip: $(pip --version 2>/dev/null || echo 'not found')"
	echo "Virtual Env: ${VIRTUAL_ENV:-none}"
	echo ""
	echo "Installed packages:"
	pip list 2> /dev/null | head -10 || echo "No packages"
}
py-deps () {
	echo "📦 Analyzing Python dependencies..."
	if [[ -f "requirements.txt" ]]
	then
		echo "requirements.txt found ($(wc -l < requirements.txt) packages)"
		grep -v "^#" requirements.txt | head -10
	fi
	if [[ -f "setup.py" ]]
	then
		echo "setup.py found"
	fi
	if [[ -f "pyproject.toml" ]]
	then
		echo "pyproject.toml found"
	fi
}
py-run () {
	local script="$1" 
	shift
	if [[ -f "$script" ]]
	then
		python3 "$script" "$@"
	else
		python3 -c "$script" "$@"
	fi
}
run-all-tests () {
	echo "🧪 Running all tests..."
	if [[ -d "tests" ]] && find tests -name "test_*.py" -o -name "*_test.py" | grep -q .
	then
		echo "Running Python tests..."
		python3 -m pytest tests/ -v
	fi
	if [[ -d "tests" ]] && find tests -name "test_*.sh" -o -name "*_test.sh" | grep -q .
	then
		echo "Running Shell tests..."
		for test in tests/test_*.sh tests/*_test.sh
		do
			[[ -f "$test" ]] && bash "$test"
		done
	fi
}
sh-check () {
	local script="${1:-.}" 
	echo "🔍 Checking shell scripts..."
	if command -v shellcheck > /dev/null 2>&1
	then
		find "$script" -name "*.sh" -type f -exec shellcheck {} \;
	else
		echo "⚠️  shellcheck not installed (brew install shellcheck)"
	fi
}
sh-format () {
	local script="${1:-.}" 
	echo "✨ Formatting shell scripts..."
	if command -v shfmt > /dev/null 2>&1
	then
		find "$script" -name "*.sh" -type f -exec shfmt -w -i 2 {} \;
	else
		echo "⚠️  shfmt not installed (brew install shfmt)"
	fi
}
sh-profile () {
	local script="$1" 
	echo "⏱️  Profiling shell script: $script"
	time bash -x "$script" 2>&1 | tail -20
}
# Shell Options
setopt nohashdirs
setopt login
# Aliases
alias -- ..='cd ..'
alias -- ...='cd ../..'
alias -- ....='cd ../../..'
alias -- .....='cd ../../../..'
alias -- ch='~/.claude/scripts/show-commands.sh'
alias -- claude-advanced='~/launch-advanced-dashboard.sh'
alias -- claude-dash='python3 ~/claude-live-dashboard.py'
alias -- claude-dashboard='~/.config/sampler/sampler-launcher-with-fixes.sh'
alias -- claude-help='~/.claude/scripts/show-commands.sh'
alias -- claude-stats='~/.config/sampler/scripts/text_dashboard.sh'
alias -- claude-term='cd ~/claude-multi-terminal && source venv/bin/activate && python3 -m claude_multi_terminal'
alias -- cmds='cat ~/.claude/COMMANDS-PANEL.txt'
alias -- commands='cat ~/.claude/COMMANDS-PANEL.txt'
alias -- cp='cp -i'
alias -- cpu='top -l 1 | grep "CPU usage"'
alias -- disk='df -h'
alias -- ff='find . -name'
alias -- gd='git diff'
alias -- gg='grep -rn'
alias -- gl='git log --oneline -10'
alias -- gp='git pull'
alias -- gs='git status'
alias -- hh='history | grep'
alias -- kill-port='function _kp(){ lsof -ti:$1 | xargs kill -9; }; _kp'
alias -- l='ls -CF'
alias -- la='ls -A'
alias -- ll='ls -lahF'
alias -- mem='top -l 1 | grep PhysMem'
alias -- mv='mv -i'
alias -- ports='lsof -i -P | grep LISTEN'
alias -- psg='ps aux | grep -v grep | grep -i -e VSZ -e'
alias -- py=python3
alias -- py-debug='python3 -m pdb'
alias -- py-format='python3 -m black'
alias -- py-freeze='pip freeze > requirements.txt'
alias -- py-install='pip install -r requirements.txt'
alias -- py-lint='python3 -m flake8'
alias -- py-path='python3 -c "import sys; print(\"\n\".join(sys.path))"'
alias -- py-profile='python3 -m cProfile -s cumulative'
alias -- py-site='python3 -m site'
alias -- py-test='python3 -m pytest'
alias -- py-trace='python3 -m trace --trace'
alias -- py-type='python3 -m mypy'
alias -- py-venv='python3 -m venv venv && source venv/bin/activate'
alias -- py-which='which python3 && python3 --version'
alias -- rm='rm -i'
alias -- run-help=man
alias -- skills='~/.claude/scripts/skills-quickref.sh'
alias -- skills-help='~/.claude/scripts/skills-quickref.sh'
alias -- skills-list='~/.claude/scripts/list-skills.sh'
alias -- skills-search='~/.claude/scripts/list-skills.sh'
alias -- tree='find . -print | sed -e "s;[^/]*/;|____;g;s;____|; |;g"'
alias -- which-command=whence
# Check for rg availability
if ! (unalias rg 2>/dev/null; command -v rg) >/dev/null 2>&1; then
  alias rg='/opt/homebrew/lib/node_modules/\@anthropic-ai/claude-code/vendor/ripgrep/arm64-darwin/rg'
fi
export PATH=/Users/wallonwalusayi/.claude/bin\:/opt/homebrew/bin\:/opt/homebrew/sbin\:/usr/local/bin\:/System/Cryptexes/App/usr/bin\:/usr/bin\:/bin\:/usr/sbin\:/sbin\:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin\:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin\:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin\:/opt/pmk/env/global/bin
