#!/bin/bash

should_init=$1
# Init

if [ "$should_init" = "init" ]; then
	if [[ -f work_log.sh ]]; then
		echo "[+] starting..."
		sudo cp work_log.sh /usr/local/bin
		sudo chmod +x /usr/local/bin/work_log.sh
		echo 'alias work_log="bash work_log.sh"' >> ~/.bash_aliases
		echo "[+] Done! Now you can run 'work_log' command from inside a project to get your work log."
		exit 0
	fi

	echo "[-] Error! You must only run the init config inside the repository folder, where the work_log.sh file is located."
	exit 1	
fi

end_date=""
start_date=""

# Get dates
echo "Select one of the date ranges below:"
select opt in "This week" "Last week"
do
	case $opt in 
		"This week")
			end_date=$(date +"%Y-%m-%d")
			start_date=$(date -d 'last Monday' +"%Y-%m-%d")
			break ;;
			
		"Last week") 
			end_date=$(date -d 'last Sunday' +"%Y-%m-%d")
			start_date=$(date -d 'last Sunday - 6 days' +"%Y-%m-%d")
			break ;;

		*) echo "Invalid option!" ;;
	esac
done

# Check and install dependencies
if ! command -v pip &> /dev/null
then
		echo "[-] You have missing dependencies (pip). Please follow this documentation: https://pip.pypa.io/en/stable/installation/"
    exit 1
fi

if ! command -v toggl &> /dev/null
then
		echo "[-] You have missing dependencies (toggl). Please install and configure it from here: https://toggl.uhlir.dev/"
		exit 1
fi

if ! command -v jq &> /dev/null
then
		echo "[-] You have missing dependencies (jq)"
		echo "[+] installing dependencies..."
    sudo apt -qq install jq &> /dev/null
fi

# Config file and values management
CONFIG_FILE=~/work_log_config.json
if ! test -f "$CONFIG_FILE"; then
	read -p "Enter your Git username: " git_username
	read -p "Enter your JIRA domain (example.atlassian.net): " jira_domain
	read -p "Enter your email (used in JIRA): " jira_email
	read -p "Enter your JIRA API token (manage your tokens from here: https://id.atlassian.com/manage-profile/security/api-tokens): " jira_api_token
	read -p "Enter the Toggl project name or id: " toggl_project
	
	echo "{\"git_username\": \"$git_username\", \"jira_domain\": \"$jira_domain\", \"jira_email\": \"$jira_email\", \"jira_api_token\": \"$jira_api_token\", \"toggl_project\": \"$toggl_project\"}" > ~/work_log_config.json
else
	git_username=$(cat $CONFIG_FILE | jq '.git_username' | sed 's/"//g')
	jira_domain=$(cat $CONFIG_FILE | jq '.jira_domain' | sed 's/"//g')
	jira_email=$(cat $CONFIG_FILE | jq '.jira_email' | sed 's/"//g')
	jira_api_token=$(cat $CONFIG_FILE | jq '.jira_api_token' | sed 's/"//g')
	toggl_project=$(cat $CONFIG_FILE | jq '.toggl_project' | sed 's/"//g')
fi

clear

# Get git history
all_history=$(git log --oneline --decorate --all --author=$git_username --after=$start_date --until=$end_date)

if [ $? = 128 ]; then
	exit 0
fi

# Get only the tickets id
for string in "$(echo $all_history | grep -Po "\[[A-Z]{2,}-[0-9]{1,}\]")"; do
	match="${match:+$match }$string"
done

# Split into an array
tickets_array=(${match// / })

# Make unique and sort
unique_tickets=($(for ticket in "${tickets_array[@]}"; do echo "${ticket}"; done | sort -u))

# Get total worked time
toggl_worked_time=$(toggl sum -st -s $start_date -p $end_date -o "$toggl_project")
toggl_worked_time_arr=(${toggl_worked_time// / })
total_worked_time="${toggl_worked_time_arr[4]}"

echo "Total worked time: $total_worked_time"
echo ""

for i in "${!unique_tickets[@]}"
do
	ticket_id=$(echo ${unique_tickets[i]} | sed 's/^.//;s/.$//')
	ticket_summary=$(curl -s https://$jira_domain/rest/api/2/issue/$ticket_id?fields=summary --user $jira_email:$jira_api_token | jq '.fields.summary' | sed 's/^.//;s/.$//')
	echo "${unique_tickets[i]} $ticket_summary" | sed 's/\\//g'
done