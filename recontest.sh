#!/bin/bash
: '
@name   ReconPi recon.sh
@author Martijn B <Twitter: @x1m_martijn>
@link   https://github.com/x1mdev/ReconPi
'

: 'Set the main variables'
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
RESET="\033[0m"
domain="$1"
RESULTDIR="$HOME/assets/$domain"
WORDLIST="$RESULTDIR/wordlists"
SUBS="$RESULTDIR/subdomains"
DIRSCAN="$RESULTDIR/directories"
HTML="$RESULTDIR/html"
GFSCAN="$RESULTDIR/gfscan"
IPS="$RESULTDIR/ips"
ARCHIVE="$RESULTDIR/archive"
VERSION="2.2"
NUCLEISCAN="$RESULTDIR/nucleiscan"


: 'Display the logo'
displayLogo() {
	echo -e "
__________                          __________.__ 
\______   \ ____   ____  ____   ____\______   \__|
 |       _// __ \_/ ___\/  _ \ /    \|     ___/  |
 |    |   \  ___/\  \__(  <_> )   |  \    |   |  |
 |____|_  /\___  >\___  >____/|___|  /____|   |__|
        \/     \/     \/           \/             
                            
			v$VERSION - $YELLOW@x1m_martijn$RESET" 
		}

	: 'Display help text when no arguments are given'
	checkArguments() {
		if [[ -z $domain ]]; then
			echo -e "[$GREEN+$RESET] Usage: recon <domain.tld>"
			exit 1
		fi
	}

checkDirectories() {
		echo -e "[$GREEN+$RESET] Creating directories and grabbing wordlists for $GREEN$domain$RESET.."
		mkdir -p "$RESULTDIR"
		mkdir -p "$SUBS"  "$DIRSCAN" "$HTML" "$WORDLIST" "$IPS"  "$ARCHIVE" "$NUCLEISCAN" "$GFSCAN"
}

startFunction() {
	tool=$1
	echo -e "[$GREEN+$RESET] Starting $tool"
}

: 'Gather resolvers'
gatherResolvers() {
	startFunction "Get fresh working resolvers"
	wget https://raw.githubusercontent.com/janmasarik/resolvers/master/resolvers.txt -O "$IPS"/resolvers.txt
}

: 'subdomain gathering'
gatherSubdomains() {
	startFunction "sublert"
	echo -e "[$GREEN+$RESET] Checking for existing sublert output, otherwise add it."
	if [ ! -e "$SUBS"/sublert.txt ]; then
		cd "$HOME"/tools/sublert || return
		yes | python3 sublert.py -u "$domain"
		cp "$HOME"/tools/sublert/output/"$domain".txt "$SUBS"/sublert.txt
		cd "$HOME" || return
	else
		cp "$HOME"/tools/sublert/output/"$domain".txt "$SUBS"/sublert.txt
	fi
	echo -e "[$GREEN+$RESET] Done, next."

	startFunction "subfinder"
	"$HOME"/go/bin/subfinder -d "$domain" -all -config "$HOME"/ReconPi/configs/config.yaml -o "$SUBS"/subfinder.txt
	echo -e "[$GREEN+$RESET] Done, next."

	startFunction "assetfinder"
	"$HOME"/go/bin/assetfinder --subs-only "$domain" >"$SUBS"/assetfinder.txt
	echo -e "[$GREEN+$RESET] Done, next."

	startFunction "amass"
	"$HOME"/go/bin/amass enum -passive -d "$domain" -config "$HOME"/ReconPi/configs/config.ini -o "$SUBS"/amassp.txt
	echo -e "[$GREEN+$RESET] Done, next."

	startFunction "findomain"
	findomain -t "$domain" -u "$SUBS"/findomain_subdomains.txt
	echo -e "[$GREEN+$RESET] Done, next."

	startFunction "chaos"
	chaos -d "$domain" -key $CHAOS_KEY -o "$SUBS"/chaos_data.txt
	echo -e "[$GREEN+$RESET] Done, next."

	startFunction "github-subdomains"
	github-subdomains -t $github_subdomains_token -d "$domain" | sort -u >> "$SUBS"/github_subdomains.txt
	echo -e "[$GREEN+$RESET] Done, next."

	startFunction  rapiddns
	crobat -s "$domain" | sort -u | tee "$SUBS"/rapiddns_subdomains.txt
	echo -e "[$GREEN+$RESET] Done, next."

	echo -e "[$GREEN+$RESET] Combining and sorting results.."
	cat "$SUBS"/*.txt | sort -u >"$SUBS"/subdomains
	echo -e "[$GREEN+$RESET] Resolving subdomains.."
	cat "$SUBS"/subdomains | sort -u | shuffledns -silent -d "$domain" -r "$IPS"/resolvers.txt > "$SUBS"/alive_subdomains
	echo -e "[$GREEN+$RESET] Getting alive hosts.."
	cat "$SUBS"/alive_subdomains | "$HOME"/go/bin/httprobe -prefer-https | tee "$SUBS"/hosts
	echo -e "[$GREEN+$RESET] Done."
}

: 'subdomain takeover check'
checkTakeovers() {
	startFunction "subjack"
	"$HOME"/go/bin/subjack -w "$SUBS"/hosts -a -ssl -t 50 -v -c "$HOME"/go/src/github.com/haccer/subjack/fingerprints.json -o "$SUBS"/all-takeover-checks.txt -ssl
	grep -v "Not Vulnerable" <"$SUBS"/all-takeover-checks.txt >"$SUBS"/takeovers
	rm "$SUBS"/all-takeover-checks.txt

	vulnto=$(cat "$SUBS"/takeovers)
	if [[ $vulnto == *i* ]]; then
		echo -e "[$GREEN+$RESET] Possible subdomain takeovers:"
		for line in "$SUBS"/takeovers; do
			echo -e "[$GREEN+$RESET] --> $vulnto "
		done
	else
		echo -e "[$GREEN+$RESET] No takeovers found."
	fi

	startFunction "nuclei to check takeover"
	cat "$SUBS"/hosts | nuclei -t subdomain-takeover/ -c 50 -o "$SUBS"/nuclei-takeover-checks.txt
	vulnto=$(cat "$SUBS"/nuclei-takeover-checks.txt)
	if [[ $vulnto != "" ]]; then
		echo -e "[$GREEN+$RESET] Possible subdomain takeovers:"
		for line in "$SUBS"/nuclei-takeover-checks.txt; do
			echo -e "[$GREEN+$RESET] --> $vulnto "
		done
	else
		echo -e "[$GREEN+$RESET] No takeovers found."
	fi
}

: 'Get all CNAME'
getCNAME() {
	startFunction "dnsprobe to get CNAMEs"
	cat "$SUBS"/subdomains | dnsprobe -r CNAME -o "$SUBS"/subdomains_cname.txt
}

: 'Gather IPs with dnsprobe'
gatherIPs() {
	startFunction "dnsprobe"
	cat "$SUBS"/subdomains | dnsprobe -silent -f ip | sort -u | tee "$IPS"/"$domain"-ips.txt
	python3 $HOME/ReconPi/scripts/clean_ips.py "$IPS"/"$domain"-ips.txt "$IPS"/"$domain"-origin-ips.txt
	echo -e "[$GREEN+$RESET] Done."
}

fetchArchive() {
	startFunction "fetchArchive"
	cat "$SUBS"/hosts | sed 's/https\?:\/\///' | gau > "$ARCHIVE"/getallurls.txt
	cat "$ARCHIVE"/getallurls.txt  | sort -u | unfurl --unique keys > "$ARCHIVE"/paramlist.txt
	cat "$ARCHIVE"/getallurls.txt  | sort -u | grep -P "\w+\.js(\?|$)" | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > "$ARCHIVE"/jsurls.txt
	cat "$ARCHIVE"/getallurls.txt  | sort -u | grep -P "\w+\.php(\?|$) | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u " > "$ARCHIVE"/phpurls.txt
	cat "$ARCHIVE"/getallurls.txt  | sort -u | grep -P "\w+\.aspx(\?|$) | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u " > "$ARCHIVE"/aspxurls.txt
	cat "$ARCHIVE"/getallurls.txt  | sort -u | grep -P "\w+\.jsp(\?|$) | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u " > "$ARCHIVE"/jspurls.txt
	echo -e "[$GREEN+$RESET] fetchArchive finished"
}

fetchEndpoints() {
	startFunction "fetchEndpoints"
	for js in `cat "$ARCHIVE"/jsurls.txt`;
	do
		python3 "$HOME"/tools/LinkFinder/linkfinder.py -i $js -o cli | anew "$ARCHIVE"/endpoints.txt;
	done
	echo -e "[$GREEN+$RESET] fetchEndpoints finished"
}
: 'Gather information with meg'
startMeg() {
	startFunction "meg"
	cd "$SUBS" || return
	meg -d 1000 -v /
	mv out meg
	cd "$HOME" || return
}

: 'Use gf to find secrets in responses'
startGfScan() {
	startFunction "Checking for secrets using gf"
	cd "$SUBS"/meg || return
	for i in `gf -list`; do [[ ${i} =~ "_secrets"* ]] && gf ${i} >> "$GFSCAN"/"${i}".txt; done
	cd "$HOME" || return
}

: 'directory brute-force'
startBruteForce() {
	startFunction "directory brute-force"
	# maybe run with interlace? Might remove
	cat "$SUBS"/hosts | parallel -j 5 --bar --shuf gobuster dir -u {} -t 50 -w wordlist.txt -l -e -r -k -q -o "$DIRSCAN"/"$sub".txt
	"$HOME"/go/bin/gobuster dir -u "$line" -w "$WORDLIST"/wordlist.txt -e -q -k -n -o "$DIRSCAN"/out.txt
}
: 'Check for Vulnerabilities'
runNuclei() {
	startFunction  "Nuclei Basic-detections"
	nuclei -l "$SUBS"/hosts -t generic-detections/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/generic-detections.txt
	startFunction  "Nuclei CVEs Detection"
	nuclei -l "$SUBS"/hosts -t cves/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/cve.txt
	startFunction  "Nuclei default-creds Check"
	nuclei -l "$SUBS"/hosts -t default-credentials/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/default-creds.txt
	startFunction  "Nuclei dns check"
	nuclei -l "$SUBS"/hosts -t dns/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/dns.txt
	startFunction  "Nuclei files check"
	nuclei -l "$SUBS"/hosts -t files/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/files.txt
	startFunction  "Nuclei Panels Check"
	nuclei -l "$SUBS"/hosts -t panels/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/panels.txt
	startFunction  "Nuclei Security-misconfiguration Check"
	nuclei -l "$SUBS"/hosts -t security-misconfiguration/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/security-misconfiguration.txt
	startFunction  "Nuclei Technologies Check"
	nuclei -l "$SUBS"/hosts -t technologies/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/technologies.txt
	startFunction  "Nuclei Tokens Check"
	nuclei -l "$SUBS"/hosts -t tokens/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/tokens.txt
	startFunction  "Nuclei Vulnerabilties Check"
	nuclei -l "$SUBS"/hosts -t vulnerabilities/ -c 50 -H "x-bug-bounty: $hackerhandle" -o "$NUCLEISCAN"/vulnerabilties.txt
	echo -e "[$GREEN+$RESET] Nuclei Scan finished"
}

notifySlack() {
	startFunction "Trigger Slack Notification"
	source "$HOME"/ReconPi/configs/tokens.txt
	export SLACK_WEBHOOK_URL="$SLACK_WEBHOOK_URL"
	echo -e "ReconPi $domain scan completed!" | slackcat
	totalsum=$(cat $SUBS/hosts | wc -l)
	echo -e "$totalsum live subdomain hosts discovered" | slackcat

	posibbletko="$(cat $SUBS/takeovers | wc -l)"
	if [ -s "$SUBS/takeovers" ]
		then
        echo -e "Found $posibbletko possible subdomain takeovers." | slackcat
	else
        echo "No subdomain takeovers found." | slackcat
	fi

	if [ -f "$NUCLEISCAN/cve.txt" ]; then
	echo "CVE's discovered:" | slackcat
    cat "$NUCLEISCAN/cve.txt" | slackcat
		else 
    echo -e "No CVE's discovered." | slackcat
	fi

	if [ -f "$NUCLEISCAN/files.txt" ]; then
	echo "files discovered:" | slackcat
    cat "$NUCLEISCAN/files.txt" | slackcat
		else 
    echo -e "No files discovered." | slackcat
	fi

	echo -e "[$GREEN+$RESET] Done."
}

: 'Execute the main functions'

source "$HOME"/ReconPi/configs/tokens.txt || return
export SLACK_WEBHOOK_URL="$SLACK_WEBHOOK_URL"

displayLogo
checkArguments
checkDirectories
gatherResolvers
gatherSubdomains
checkTakeovers
getCNAME
gatherIPs
startMeg
#fetchArchive
#fetchEndpoints
startGfScan
runNuclei
#makePage
notifySlack

# Uncomment the functions
