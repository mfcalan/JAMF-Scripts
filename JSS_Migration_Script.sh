#!/bin/bash


# Script to migrate to a new JSS
# xmlstarlet is used to modify the xmls before they are uploaded to the new JSS
# The script will run a health check on the source JSS, it is looking for any duplicate entires such as
# 2 computer records with the same serial number, UDID or name. Or records that are missing that info.
# A comparison is also done between the source and destination JSS. Any duplicate names that are found in both locations
# will be logged and you will be asked if you would like to rename them in the source. This will modify the name to add the record
# id to the end of the name.
# Once the checks are made and any potential problems addressed the migration will begin.
# You get the choice to cycle through the resources automatically or manually choose what to migrate.
# There is a specific order that resources should be migrated, not following this order can result in resources failing to post
# There is also the option to specify xmls to be uploaded, useful if you alrady have a xml you know is good to upload
# A lot of the resource xmls contain the id for a different resource. For example a policy xml will have the id for the category it is assigned to,
# any scope ids (computers, groups), package/script ids and so on.
# These all need to be updated to the new id or the resource will fail to post therefore each time a resource is completed a full list of 
# resource ids will be downloaded from the destination and used to update future ids

##########################################################################################
##########################################################################################
## MANUAL VARIABLES
###

localOutputDirectory="$HOME/Desktop/JSS_Migration"

####### if these are left empty you will be prompted for them by the script
oldjss=""
old_jss_apiuser=""
old_jss_apipass=""
newjss=""
new_jss_apiuser=""
new_jss_apipass=''
computer_management_pw=''

new_site_id=""		#id for the site we are moving to, you can get this by going to https://yourjssaddress.com:8443/JSSResource/sites
new_site_name=""	#name of site we are moving to
########

######## DO NOT MODIFY BELOW THIS LINE ########

osascript -e 'Tell application "System Events" to display dialog "It is critical that you have accounts on both JSS instances with the correct API access levels." & return & "" & return & "On the source JSS, you need read access.  On the destination JSS, you need full read and write access." & return & "" & return & "At any time during this script, you may abort with the standard Control - C keys." buttons {"Continue"} default button "Continue"'

##########################################################################################
#INSTALL XMLSTARLET
# xmlstarlet is required to run this script
# if it's not already installed it will be installed now
if [ -x /usr/local/Cellar/xmlstarlet ]; then
	echo -e "\nxmlstarlet is installed\n\n"
else
	echo -e "xmlstarlet needs to be installed.\nThis requires the xcode Developer Tools and Homebrew.\n"
	# in order to install xmlstarlet we need to install the xcode developer tools and Homebrew	
	# check if the command dev tools are installed by trying to run one of the tools
	# if it's not installed you will be prompted by the OS to install them
	svn
	
	# check processes for Install Command Line Developer Tools, 
	# if it is running the developer tools are being installed so wait for it to finish
	sleep 2
	installingDevTools=$(pgrep 'Install Command Line Developer Tools')
	if [[ ! "${installingDevTools}" = "" ]]; then
		echo -e "\nDev tools are installing: PID $installingDevTools\nPlease wait...\n"
	fi	

	while [[ ! "${installingDevTools}" = "" ]]
		do
    		sleep 3
    		installingDevTools=$(pgrep 'Install Command Line Developer Tools')
		done

	echo -e "\nDeveloper Tools are installed\n"

	# install homebrew if needed
	if [ -x /usr/local/bin/brew ]; then
		echo -e "\nHomebrew is installed\n"
	else
		echo -e "\nInstalling Homebrew\n"
		/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
	fi
	
	# use Homebrew to install xmlstarlet
	echo -e "\nInstalling xmlstarlet\n"
	brew install xmlstarlet
	echo -e "\nxmlstarlet has been installed\n"
fi
##########################################################################################
# PROMPT FOR VARIABLES
######## Prompt for variable for old JSS address
if [ -z "$oldjss" ]; then
	oldjss="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Enter OLD JSS Address with no trailing slash:" default answer "https://yourjssaddress.com:8443"' -e 'text returned of result' -e 'end timeout' 2>/dev/null)"
	if [ $? -ne 0 ]; then
   	# The user pressed Cancel
    	exit 0
	elif [ -z "$oldjss" ]; then
    	# The user left the project name blank
   		osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "You must enter a JSS Address; cancelling..."' -e 'end timeout'
    	exit 1 # exit with an error status
	fi
fi	

######## Prompt for new JSS Address and adds variable
if [ -z "$newjss" ]; then
	newjss="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Enter NEW JSS Address no trailing slash:" default answer "https://wk.jamfcloud.com"' -e 'text returned of result' 2>/dev/null) -e 'end timeout'"
	if [ $? -ne 0 ]; then
   		# The user pressed Cancel
    	exit 0
	elif [ -z "$newjss" ]; then
    	# The user left the project name blank
    	osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "You must enter a JSS Address; cancelling..." as warning' -e 'end timeout'
    	exit 1 # exit with an error status
	fi
fi

######## Prompt for old server api user and adds variable
if [ -z "$old_jss_apiuser" ]; then
	old_jss_apiuser="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Enter API username for the OLD JSS:" default answer ""' -e 'text returned of result' -e 'end timeout' 2>/dev/null)"
	if [ $? -ne 0 ]; then
    	# The user pressed Cancel
    	exit 0
	elif [ -z "$old_jss_apiuser" ]; then
    	# The user left the project name blank
    	osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "You must enter a api user; cancelling..."' -e 'end timeout'
    	exit 1 # exit with an error status
	fi
fi

######## Prompt for password for API users and adds variable
if [ -z "$old_jss_apipass" ]; then
	old_jss_apipass="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Enter API password for the OLD JSS Password:" default answer "" with hidden answer' -e 'text returned of result' -e 'end timeout' 2>/dev/null)"
	if [ $? -ne 0 ]; then
    	# The user pressed Cancel
    	exit 0
	elif [ -z "$old_jss_apipass" ]; then
    	# The user left the project name blank
    	osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "You must enter a password; cancelling..." as warning' -e 'end timeout'
    	exit 1 # exit with an error status
	fi
fi

######## Prompt for old server api user and adds variable
if [ -z "$new_jss_apiuser" ]; then
	new_jss_apiuser="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Enter API username for the NEW JSS:" default answer ""' -e 'text returned of result' -e 'end timeout' 2>/dev/null)"
	if [ $? -ne 0 ]; then
    	# The user pressed Cancel
    	exit 0
	elif [ -z "$new_jss_apiuser" ]; then
    	# The user left the project name blank
    	osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "You must enter a api user; cancelling..." as warning' -e 'end timeout'
    	exit 1 # exit with an error status
	fi
fi

######## Prompt for password for API users and adds variable
if [ -z "$new_jss_apipass" ]; then
	new_jss_apipass="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Enter API password for the NEW JSS Password:" default answer "" with hidden answer' -e 'text returned of result' -e 'end timeout' 2>/dev/null)"
	if [ $? -ne 0 ]; then
    	# The user pressed Cancel
    	exit 0
	elif [ -z "$new_jss_apipass" ]; then
    	# The user left the project name blank
    	osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "You must enter a password; cancelling..." as warning' -e 'end timeout'
    	exit 1 # exit with an error status
	fi
fi

######## Prompt for password for API users and adds variable
if [ -z "$computer_management_pw" ]; then
	computer_management_pw="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Enter the computer management password (this is the password used by the JSS to manage the computers):" default answer "" with hidden answer' -e 'text returned of result' -e 'end timeout' 2>/dev/null)"
	if [ $? -ne 0 ]; then
    	# The user pressed Cancel
    	exit 0
	elif [ -z "$new_jss_apipass" ]; then
    	# The user left the project name blank
    	osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "You must enter a password; cancelling..." as warning' -e 'end timeout'
    	exit 1 # exit with an error status
	fi
	computer_management_pw_confirm="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Please confim the computer management password:" default answer "" with hidden answer' -e 'text returned of result' -e 'end timeout' 2>/dev/null)"
	if [ $? -ne 0 ]; then
		# User cancelled
		exit 0
	else	
		if [[ ! $computer_management_pw = $computer_management_pw_confirm ]];then
			osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display alert "The passwords do not match; cancelling..." as warning' -e 'end timeout'
    		exit 1 # exit with an error status
    	fi
    fi		
fi

##########################################################################################
##########################################################################################
# FUNCTIONS
###

# Prompt for site to migrate to and add variable for name and id
getMigrationSite ()
{
if [[ $new_site_name == "" ]] || [[ $new_site_id == "" ]]; then
	curl -k "$newjss"/JSSResource/sites --user "${new_jss_apiuser}":"${new_jss_apipass}" | xmllint --format - > /tmp/sites.xml
	NumberOfSites=$(xmllint --xpath "string(//sites/size)" /tmp/sites.xml)
	if [[ $NumberOfSites == "" ]]; then
		osascript -e 'with timeout of 7200 seconds' -e 'set newjss to do shell script "echo '"${newjss}"'"' -e 'Tell application "System Events" to display dialog "There were no sites found on " & newjss &"" & return & "" & return & "If this is not correct then fix it before continuing or no site will be assigned." buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
		if [ ! $? -eq 0 ]; then
			echo "User chose to exit"
			exit 0
		else	
			new_site_name="None"
			new_site_id="-1"
		fi
	else			
		counter=1

		while [ $counter -le $NumberOfSites ]
		do
			SiteID=$(xmllint --xpath "string(//sites/site [$counter])" /tmp/sites.xml | awk 'NR==2' | sed 's|^[[:blank:]]*||g')
			SiteName=$(xmllint --xpath "string(//sites/site [$counter])" /tmp/sites.xml | awk 'NR==3' | sed 's|^[[:blank:]]*||g')
			echo "${SiteID} ${SiteName}" >> /tmp/site_list_and_id
			echo "${SiteName}" >> /tmp/sites_names
			counter=$(( $counter + 1 ))
		done

		selectedSite=`osascript <<-AppleScript
		set siteListLong to (do shell script "cat /tmp/sites_names")
		set {oldtid, AppleScript's text item delimiters} to {AppleScript's text item delimiters, return}
		set siteList to every text item of siteListLong
		tell application "System Events"
			activate
			with timeout of 7200 seconds
			choose from list siteList with prompt "Please a choose site to migrate to:"
			 end timeout
		end tell
		AppleScript`

		selectedSiteID=$(grep "$selectedSite" </tmp/site_list_and_id | awk '{print $1}' )

		rm /tmp/site*

		new_site_name="$selectedSite"
		new_site_id="$selectedSiteID"
	fi		
fi

if [[ $new_site_name == "" ]]; then
	echo -e "\n\nError - new site name is not set\n\n"
	exit 1
else
	echo  "New site name: ${new_site_name}"	
fi

if [[ $new_site_id == "" ]]; then
	echo -e "\n\nError - new site id is not set\n\n"
	exit 1
else
	echo "New site id: ${new_site_id}"
fi

if [[ ! $seen_final_check == "YES" ]]; then
	osascript -e 'with timeout of 7200 seconds' -e 'set site to do shell script "echo '"${new_site_name}"'"' -e 'set newjss to do shell script "echo '"${newjss}"'"' -e 'set oldjss to do shell script "echo '"${oldjss}"'"' -e 'Tell application "System Events" to display dialog "One last check before we begin." & return & "" & return & "We are going to copy FROM:" & return & "" & return & "" & oldjss &"" & return & "" & return & " TO the " & site &" site at:" & return & "" & return & "" & newjss &"" & return & "" & return & "" buttons {"Exit", "Continue"} cancel button "Exit" default button "Continue"' -e 'end timeout'
	if (( ! $? == 0 )); then 
		echo "User chose to exit"
		exit 0
	else
		seen_final_check=YES	
	fi
fi

}

##########################################################################################
initializeDirectoriesPerResource ()
{
echo "Creating local directories for $jssResource ..."
if [ -d "$localOutputDirectory"/"$jssResource" ]
	then
		echo "Found existing directory for $jssResource -- Archiving..."
			if [ -d "$localOutputDirectory"/archives ]; then
				echo "Archive directory exists"
			else 
				echo "Archive directory does not exist.  Creating..."
				mkdir "$localOutputDirectory"/archives
			fi
		ditto -ck "$localOutputDirectory"/"$jssResource" "$localOutputDirectory"/archives/"$jssResource"-$(date +%Y%m%d%H%M%S).zip
		echo "Removing previous local directory structure for $jssResource"
		rm -rf "$localOutputDirectory"/"$jssResource"
	else
		echo "No previous directories found for $jssResource"
fi

mkdir -p "$localOutputDirectory/$jssResource"/id_list
mkdir -p "$localOutputDirectory/$jssResource"/new_id_list
mkdir -p "$localOutputDirectory/$jssResource"/fetched_xml
mkdir -p "$localOutputDirectory/$jssResource"/edited_xml
mkdir -p "$localOutputDirectory/$jssResource"/completed_xml
mkdir -p "$localOutputDirectory/$jssResource"/failed_xml
mkdir -p "$localOutputDirectory/$jssResource"/failed_xml/failed_to_upload
mkdir -p "$localOutputDirectory/$jssResource"/failed_xml/failed_to_edit
mkdir -p "$localOutputDirectory/$jssResource"/failed_xml/failed_to_get_id
mkdir -p "$localOutputDirectory/$jssResource"/failed_xml/failed_to_update_id
mkdir -p "$localOutputDirectory/$jssResource"/failed_xml/failed_invalid_xml

echo -e "\nDirectories created\n"
}

##########################################################################################

setVariablesForResource ()
{
formattedList="$localOutputDirectory"/"$jssResource"/id_list/formattedList.xml
plainList="$localOutputDirectory"/"$jssResource"/id_list/plainList
plainListAccountsUsers="$localOutputDirectory"/"$jssResource"/id_list/plainListAccountsUsers
plainListAccountsGroups="$localOutputDirectory"/"$jssResource"/id_list/plainListAccountsGroups
resultInt=1
}

##########################################################################################

createIDlist ()
{
echo -e "\nFetching XML data for $jssResource ID's"
#curl -k "$oldjss"/JSSResource/"$jssResource" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xmllint --format - > $formattedList
/usr/bin/curl -k -u "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" "{$oldjss}"/JSSResource/"${jssResource}" -X GET | xmllint --format - > $formattedList
curlStatus=$(cat $formattedList)
if [[ $curlStatus == "" ]]; then
	echo "Failed to download $jssResource ID's"
	osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set curlStatus to do shell script "echo '"${curlStatus}"'"' -e 'set oldjss to do shell script "echo '"${oldjss}"'"' -e 'Tell application "System Events" to display dialog "Failed to download " & jssResource &" IDs from " & oldjss &"." & return & "" & return & "Do you want to skip " & jssResource &" and continue?" buttons {"Exit", "Skip"} cancel button "Exit" default button "Skip" with icon caution' -e 'end timeout'
	if (( ! $? == 0 )); then 
		echo "User chose to exit"
		exit 0
	else 
		failed=YES	
	fi
fi	

if [ "$jssResource" = "accounts" ]
	then
		echo "For accounts resource - we need two separate lists"
		echo "Creating plain list of user ID's..."
		sed -e '/<site>/,/<\/site>/d' -e '/<groups>/,/<\/groups>/d' $formattedList | awk -F '<id>|</id>' '/<id>/ {print $2}' > $plainListAccountsUsers
		echo "Creating plain list of group ID's..."
		sed -e '/<site>/,/<\/site>/d' -e '/<users>/,/<\/users>/d' $formattedList | awk -F '<id>|</id>' '/<id>/ {print $2}' > $plainListAccountsGroups
	else
		echo -e "\n\nCreating a plain list of $jssResource ID's \n"
		awk -F'<id>|</id>' '/<id>/ {print $2}' $formattedList > $plainList
fi
echo -e "\n\n\n"
sleep 3
}

##########################################################################################

fetchResourceXML ()
{
if [ "$jssResource" = "accounts" ]; then
	
	totalFetchedIDsUsers=$(wc -l <"$plainListAccountsUsers" | sed -e 's/^[ \t]*//')
	for apiID in $(cat $plainListAccountsUsers)
		do
			echo "Downloading User ID number $apiID ( $resultInt out of $totalFetchedIDsUsers )"
			curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/accounts/userid/$apiID | xmllint --format - > "$localOutputDirectory"/"$jssResource"/fetched_xml/userResult_"$apiID".xml
			curlStatus=$?
			if (( ! $? == 0 )); then
				echo "Failed to download User ID number $apiID"
				osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set curlStatus to do shell script "echo '"${curlStatus}"'"' -e 'set oldjss to do shell script "echo '"${oldjss}"'"' -e 'Tell application "System Events" to display dialog "Failed to download " & jssResource &" User ID number from " & oldjss &"." & return & "" & return & "Curl Status: " & curlStatus &""& return & "" & return & "Do you want to continue?" buttons {"Exit", "Continue"} cancel button "Exit" default button "Continue" with icon caution' -e 'end timeout'
				if (( ! $? == 0 )); then
					echo "User chose to exit"
					exit 0
				fi
			fi	
			# check we have a valid xml
			validate_xml="$(xml val "$localOutputDirectory"/"$jssResource"/fetched_xml/userResult_"$apiID".xml | awk '{print $NF}')"					
			if [[ ! $validate_xml == "valid" ]]; then
				echo "***** ERROR: not a valid xml - userResult_"$apiID".xml******"
				echo "userResult_"$apiID".xml ERROR: not a valid xml" >> "$localOutputDirectory/$jssResource/failed_xml/_"$jssResource"_error.log"
				errorButton="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set apiID to do shell script "echo '"${apiID}"'"' -e 'Tell application "System Events" to display dialog "" & jssResource &" userResult_" & apiID &".xml is not a valid xml." & return & "" & return & "What do you want to do?" buttons {"Exit", "Continue", "Download Again"} cancel button "Exit" default button "Download Again" with icon caution' -e 'button returned of result' -e 'end timeout')"
				if [[ $errorButton == "Exit" ]]; then
					echo "User chsoe to exit"			
					mv "$localOutputDirectory"/"$jssResource"/fetched_xml/userResult_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/userResult_"$apiID".xml
					exit 1
				elif [[ $errorButton == "Continue" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/fetched_xml/userResult_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/userResult_"$apiID".xml		
				else
					echo "Downloading userResult_"$apiID".xml again"
					curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/accounts/userid/$apiID | xmllint --format - > "$localOutputDirectory"/"$jssResource"/fetched_xml/userResult_"$apiID".xml	
					validate_xml="$(xml val "$localOutputDirectory"/"$jssResource"/fetched_xml/userResult_"$apiID".xml | awk '{print $NF}')"					
					if [[ ! $validate_xml == "valid" ]]; then
						osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set apiID to do shell script "echo '"${apiID}"'"' -e 'Tell application "System Events" to display dialog "" & jssResource &" userResult_" & apiID &".xml is not a valid xml." & return & "" & return & "What do you want to do?" buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
						if [ ! $? -eq 0 ]; then
							echo "User chose to exit"
						else
							mv "$localOutputDirectory"/"$jssResource"/fetched_xml/userResult_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/userResult_"$apiID".xml				
						fi
					else
						echo "Valid xml"
					fi
				fi				
			fi
			let "resultInt = $resultInt + 1"
		done
	resultInt=1
	totalFetchedIDsGroups=$(wc -l <"$plainListAccountsGroups" | sed -e 's/^[ \t]*//')
	for apiID in $(cat $plainListAccountsGroups)
		do
			echo "Downloading Group ID number $apiID ( $resultInt out of $totalFetchedIDsGroups )"
			curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/accounts/groupid/$apiID | xmllint --format - > "$localOutputDirectory"/"$jssResource"/fetched_xml/groupResult_"$apiID".xml
			curlStatus=$?
			if (( ! $? == 0 )); then
				echo "Failed to download Group ID number $apiID"
				osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set curlStatus to do shell script "echo '"${curlStatus}"'"' -e 'set oldjss to do shell script "echo '"${oldjss}"'"' -e 'Tell application "System Events" to display dialog "Failed to download " & jssResource &" Group ID number from " & oldjss &"." & return & "" & return & "Curl Status: " & curlStatus &""& return & "" & return & "Do you want to continue?" buttons {"Exit", "Continue"} cancel button "Exit" default button "Continue" with icon caution' -e 'end timeout'
				if (( ! $? == 0 )); then
					echo "User chose to exit"
					exit 0
				fi
			fi		
			validate_xml="$(xml val "$localOutputDirectory"/"$jssResource"/fetched_xml/groupResult_"$apiID".xml | awk '{print $NF}')"					
			if [[ ! $validate_xml == "valid" ]]; then
				echo "***** ERROR: not a valid xml - groupResult_"$apiID".xml******"
				echo "groupResult_"$apiID".xml ERROR: not a valid xml" >> "$localOutputDirectory/$jssResource/failed_xml/_"$jssResource"_error.log"
				errorButton="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set apiID to do shell script "echo '"${apiID}"'"' -e 'Tell application "System Events" to display dialog "" & jssResource &" groupResult_" & apiID &".xml is not a valid xml." & return & "" & return & "What do you want to do?" buttons {"Exit", "Continue", "Download Again"} cancel button "Exit" default button "Download Again" with icon caution' -e 'button returned of result' -e 'end timeout')"
				if [[ $errorButton == "Exit" ]]; then
					echo "User chose to exit"			
					mv "$localOutputDirectory"/"$jssResource"/fetched_xml/groupResult_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/groupResult_"$apiID".xml
					exit 1
				elif [[ $errorButton == "Continue" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/fetched_xml/groupResult_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/groupResult_"$apiID".xml		
				else
					echo "Downloading groupResult_"$apiID".xml again"
					curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/accounts/groupid/$apiID | xmllint --format - > "$localOutputDirectory"/"$jssResource"/fetched_xml/groupResult_"$apiID".xml	
					validate_xml="$(xml val "$localOutputDirectory"/"$jssResource"/fetched_xml/groupResult_"$apiID".xml | awk '{print $NF}')"					
					if [[ ! $validate_xml == "valid" ]]; then
						osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set apiID to do shell script "echo '"${apiID}"'"' -e 'Tell application "System Events" to display dialog "" & jssResource &" groupResult_" & apiID &".xml is not a valid xml." & return & "" & return & "What do you want to do?" buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
						if [ ! $? -eq 0 ]; then
							echo "User chose to exit"
						else
							mv "$localOutputDirectory"/"$jssResource"/fetched_xml/groupResult_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/groupResult_"$apiID".xml
						fi
					else
						echo "Valid xml"
					fi
				fi				
			fi			
			let "resultInt = $resultInt + 1"
		done
else
	totalFetchedIDs=$(wc -l <"$plainList" | sed -e 's/^[ \t]*//')
	for apiID in $(cat $plainList)
		do
			echo "Downloading ID number $apiID ( $resultInt out of $totalFetchedIDs )"
			curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/$jssResource/id/$apiID | xmllint --format - > "$localOutputDirectory"/"$jssResource"/fetched_xml/result_"$apiID".xml
			curlStatus=$?
			if (( ! $? == 0 )); then
				echo "Failed to download ID number $apiID"
				osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set curlStatus to do shell script "echo '"${curlStatus}"'"' -e 'set oldjss to do shell script "echo '"${oldjss}"'"' -e 'Tell application "System Events" to display dialog "Failed to download " & jssResource &" ID number from " & oldjss &"." & return & "" & return & "Curl Status: " & curlStatus &""& return & "" & return & "Do you want to continue?" buttons {"Exit", "Continue"} cancel button "Exit" default button "Continue" with icon caution' -e 'end timeout'
				if (( ! $? == 0 )); then
					echo "User chose to exit"
					exit 0
				fi
				
				validate_xml="$(xml val "$localOutputDirectory"/"$jssResource"/fetched_xml/result_"$apiID".xml | awk '{print $NF}')"					
				if [[ ! $validate_xml == "valid" ]]; then
					echo "***** ERROR: not a valid xml - result_"$apiID".xml******"
					echo "result_"$apiID".xml ERROR: not a valid xml" >> "$localOutputDirectory/$jssResource/failed_xml/_"$jssResource"_error.log"
					errorButton="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set apiID to do shell script "echo '"${apiID}"'"' -e 'Tell application "System Events" to display dialog "" & jssResource &" result_" & apiID &".xml is not a valid xml." & return & "" & return & "What do you want to do?" buttons {"Exit", "Continue", "Download Again"} cancel button "Exit" default button "Download Again" with icon caution' -e 'button returned of result' -e 'end timeout')"
					if [[ $errorButton == "Exit" ]]; then
						echo "User chose to exit"			
						mv "$localOutputDirectory"/"$jssResource"/fetched_xml/result_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/result_"$apiID".xml
						exit 1
					elif [[ $errorButton == "Continue" ]]; then
						mv "$localOutputDirectory"/"$jssResource"/fetched_xml/result_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/result_"$apiID".xml		
					else
						echo "Downloading result_"$apiID".xml again"
						curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/$jssResource/id/$apiID | xmllint --format - > "$localOutputDirectory"/"$jssResource"/fetched_xml/result_"$apiID".xml
						validate_xml="$(xml val "$localOutputDirectory"/"$jssResource"/fetched_xml/result_"$apiID".xml | awk '{print $NF}')"					
						if [[ ! $validate_xml == "valid" ]]; then
							osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'set apiID to do shell script "echo '"${apiID}"'"' -e 'Tell application "System Events" to display dialog "" & jssResource &" result_" & apiID &".xml is not a valid xml." & return & "" & return & "What do you want to do?" buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
							if [ ! $? -eq 0 ]; then
								echo "User chose to exit"
							else
								mv "$localOutputDirectory"/"$jssResource"/fetched_xml/result_"$apiID".xml > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_invalid_xml/result_"$apiID".xml
							fi
						else
							echo "Valid xml"
						fi
					fi				
				fi				
			fi
			let "resultInt = $resultInt + 1"
		done
fi
}

##########################################################################################

xmlNodeName ()
{

# xmlstarlet needs to know the node name for the element it is trying to edit, these variy depending on the resource
if [[ $jssResource == "categories" ]]; then	
	xmlNode="category"
elif [[ $jssResource == "ldapservers" ]]; then
	xmlNode="ldap_server"
elif [[ $jssResource == "accounts" ]]; then
	# if this is a group account change the xml node to group
	if [[ $resourceXML == groupResult* ]]; then
		xmlNode="group"
	else
		xmlNode="account"
	fi
elif [[ $jssResource == "buildings" ]]; then
	xmlNode="building"
elif [[ $jssResource == "departments" ]]; then
	xmlNode="department"
elif [[ $jssResource == "computerextensionattributes" ]]; then
	if [[ "$updating_ids" == "YES" ]]; then
		xmlNode="extension_attribute"
	else
		xmlNode="computer_extension_attribute"
	fi	
elif [[ $jssResource == "directorybindings" ]]; then
	xmlNode="directory_binding"
elif [[ $jssResource == "dockitems" ]]; then
	xmlNode="dock_item"
elif [[ $jssResource == "removablemacaddresses" ]]; then
	xmlNode="removable_mac_address"
elif [[ $jssResource == "printers" ]]; then
	xmlNode="printer"
elif [[ $jssResource == "licensedsoftware" ]]; then
	xmlNode="licensed_software"
elif [[ $jssResource == "scripts" ]]; then
	xmlNode="script"
elif [[ $jssResource == "netbootservers" ]]; then
	xmlNode="netboot_server"
elif [[ $jssResource == "computers" ]]; then
	xmlNode="computer"
elif [[ $jssResource == "distributionpoints" ]]; then
	xmlNode="distribution_point"
elif [[ $jssResource == "softwareupdateservers" ]]; then
	xmlNode="software_update_server"
elif [[ $jssResource == "networksegments" ]]; then
	xmlNode="network_segment"
elif [[ $jssResource == "computergroups" ]]; then
	xmlNode="computer_group"
elif [[ $jssResource == "osxconfigurationprofiles" ]]; then
	xmlNode="os_x_configuration_profile"
elif [[ $jssResource == "restrictedsoftware" ]]; then
	xmlNode="restricted_software"
elif [[ $jssResource == "packages" ]]; then
	xmlNode="package"
elif [[ $jssResource == "policies" ]]; then
	xmlNode="policy"
elif [[ $jssResource == "advancedcomputersearches" ]]; then
	xmlNode="advanced_computer_search"
elif [[ $jssResource == "managedpreferenceprofiles" ]]; then
	xmlNode="managed_preference_profile"
elif [[ $jssResource == "computerconfigurations" ]]; then
	xmlNode="computer_configuration"
elif [[ $jssResource == "macapplications" ]]; then
	xmlNode="mac_application"
elif [[ $jssResource == "peripheraltypes" ]]; then
	xmlNode="peripheral_type"
elif [[ $jssResource == "peripherals" ]]; then
	xmlNode="peripheral"	
fi	

}

##########################################################################################
	
editResourceXML ()
{
echo -e "\n\nProceeding to edit each downloaded XML file..."
number_of_id_update_errors=0
number_of_xmls=$(ls "$localOutputDirectory"/"$jssResource"/fetched_xml/ | wc -l | sed 's/^ *//g')
xml_count=1

if [ "$jssResource" = "categories" ]; then
	echo "For $jssResource - no need for extra special Editing.  Simply removing references to ID's"
	for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
		do
			echo "Editing $resourceXML "
			category=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML  2>/dev/null)
			category_upper=$(echo "$category" | tr [a-z] [A-Z])
			xml ed -d "/$xmlNode/id" -u "/category/name" -v "$category_upper" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML"
			validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
			if [[ $validate_xml == "valid" ]]; then
				echo "Successfully edited $resourceXML"
			else
				echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
				mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
				echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
			fi
			xml_count=$(( $xml_count + 1 ))
		done
elif [ "$jssResource" = "accounts" ]; then
	# LDAP servers must be migrated first, passwords will not be included with standard accounts
	osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Very important info regarding Accounts:" & return & "" & return & "1. If you have LDAP-based JSS Admin accounts, you must migrate LDAP Servers first." & return & "" & return & "2. Passwords WILL NOT be included with standard accounts. Enter them manually in the JSS." buttons {"Cancel", "Continue"} default button "Continue" with icon caution' -e 'end timeout'
	if (( $? == 0 )); then
		echo -e "\n\n"
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				xmlNodeName
				xml_to_update="$resourceXML"
				# remove the id and add the site and new LDAP id using xmlstarlet
				xml_file=$(xml ed -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" -d "/$xmlNode/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)				
				updateIDs
				echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
				# check we have a valid xml
				validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"
				if [[ $validate_xml == "valid" ]]; then
					echo "Successfully edited $resourceXML"
				else
					echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
					mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
					echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
				fi
				if [[ $id_update_error == "YES" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
				fi
				xml_count=$(( $xml_count + 1 ))			
			done
	else
		echo "User cancelled"
		exit 0
	fi				
elif [ "$jssResource" = "computergroups" ]; then
	echo -e "\n\nProceeding to edit each downloaded XML file..."
	xmlNodeName
	scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfGroups to do shell script "echo '"${totalFetchedIDs}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfGroups &" " & jssResource &" were found. Do you want to keep the computers in the scope?" & return & "" & return & "Keeping the computers will increase the time it takes to edit the xmls drastically as each id will need to be updated." & return & "" & return & "What do you want to do?" buttons {"Remove Computers", "Keep Computers"} with icon caution' -e 'button returned of result' -e 'end timeout')"
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "				
				if [[ $(grep "<is_smart>false</is_smart>" <"$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML) ]]; then
					echo "$resourceXML is a STATIC computer group..."			
					xml_to_update="$resourceXML"
					# remove the id and add the site and new LDAP id using xmlstarlet
					if [[ $scopeChoice == "Remove Computers" ]]; then
						echo "removing computers from scope"
						xml_file=$(xml ed -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" -d "/$xmlNode/id" -d "//computers" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					elif [[ $scopeChoice == "Keep Computers" ]]; then		
						echo "keeping computers in scope"
						xml_file=$(xml ed -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" -d "/$xmlNode/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					fi					
					updateIDs
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/static_group_edited_"$resourceXML"
					# check we have a valid xml
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/static_group_edited_$resourceXML | awk '{print $NF}')"
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						mv "$localOutputDirectory"/"$jssResource"/edited_xml/static_group_edited_"$resourceXML" > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/static_group_edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi			
					if [[ $id_update_error == "YES" ]]; then
						mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
					fi		
				else
					echo "$resourceXML is a SMART computer group..."
					xml_to_update="$resourceXML"
					# remove the id and add the site and new LDAP id using xmlstarlet
					if [[ $scopeChoice == "Remove Computers" ]]; then
						echo "removing computers from scope"
						xml_file=$(xml ed -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" -d "/$xmlNode/id" -d "//computers" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					elif [[ $scopeChoice == "Keep Computers" ]]; then		
						echo "keeping computers in scope"
						xml_file=$(xml ed -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" -d "/$xmlNode/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					fi					
					updateIDs
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/smart_group_edited_"$resourceXML"
					# check we have a valid xml
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/smart_group_edited_$resourceXML | awk '{print $NF}')"
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						mv "$localOutputDirectory"/"$jssResource"/edited_xml/smart_group_edited_"$resourceXML" > "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/smart_group_edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi		
				fi							
				if [[ $id_update_error == "YES" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
				fi	
				xml_count=$(( $xml_count + 1 ))	
			done		
elif [ "$jssResource" = "computers" ]
	then
		xmlNodeName
		number_of_eas=$(ls "$localOutputDirectory"/computerextensionattributes/fetched_xml/ | wc -l | sed 's/^ *//g')
		# ask if we want to keep the EA info, keeping it increases the time it takes to update the xml ids
		scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfEAs to do shell script "echo '"${number_of_eas}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfEAs & " extension attributes were found. Do you want to keep the data for these?" & return & "" & return & "Keeping the data will increase the time it takes to edit the xmls drastically as each EA will need to be updated for each computer." & return & "" & return & "What do you want to do?" buttons {"Remove EAs", "Keep EAs"} with icon caution' -e 'button returned of result' -e 'end timeout')"
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"
				# in order to post computers we need to strip out the management account password hash and replace it with a clear text password, EA's also need to be removed along with the recored id and update the site
				# we also remove the alternate MAC address as we can get duplicates if more than one person has used a device with a removable mac address thats not white listed in the jss.
				if [[ $scopeChoice == "Keep EAs" ]]; then
					xml_file=$(xml ed -d "/$xmlNode/general/alt_mac_address" -d "/$xmlNode/general/id" -d "/$xmlNode/general/remote_management/management_password_sha256" --subnode "/$xmlNode/general/remote_management" --type elem -n management_password -v "$computer_management_pw" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				else
					# remove the EA data
					xml_file=$(xml ed -d "//extension_attributes" -d "/$xmlNode/general/alt_mac_address" -d "/$xmlNode/general/id" -d "/$xmlNode/general/remote_management/management_password_sha256" --subnode "/$xmlNode/general/remote_management" --type elem -n management_password -v "$computer_management_pw" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				fi	
				updateIDs
				echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
				validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"
				if [[ $validate_xml == "valid" ]]; then
					echo "Successfully edited $resourceXML"
				else
					echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
					mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
				fi	
				if [[ $id_update_error == "YES" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
					echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
				fi	
				xml_count=$(( $xml_count + 1 ))	
			done						
elif [ "$jssResource" = "distributionpoints" ]
	then
		xmlNodeName
		echo -e "\n**********\n\nVery Important Info regarding Distribution Points -- "
		echo -e "\n\n1. Failover settings will NOT be included in migration!"
		echo "2. Load balancing settings will NOT be included in migration!"
		echo "3. Passwords for Casper Read and Casper Admin accounts will NOT be included in migration!"		
		echo -e "\nThese must be set manually in web app\n\n**********\n\n"
		osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Very important info regarding Distribution Points:" & return & "" & return & "1. Failover settings will NOT be included in migration!" & return & "" & return & "2. Load balancing settings NOT be included in migration!" & return & "" & return & "3. Passwords for Casper Read and Casper Admin accounts will NOT be included in migration!" & return & "" & return & "These must be set manually in JSS."  buttons {"Continue"} default button "Continue" with icon caution' -e 'end timeout'
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"				
				# for DPs we need to remove the id and any failover references as well as load balancing
				xml_file=$(xml ed -d "/$xmlNode/id" -d "/$xmlNode/failover_point" -d "/$xmlNode/failover_point_url" -d "/$xmlNode/enable_load_balancing" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 				
				validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"		
				if [[ $validate_xml == "valid" ]]; then
					echo "Successfully edited $resourceXML"
				else
					echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
					mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
					echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
				fi	
				xml_count=$(( $xml_count + 1 ))
			done
elif [ "$jssResource" = "ldapservers" ]
	then
		xmlNodeName
		echo -e "\n**********\n\nVery Important Info regarding LDAP Servers -- "
		echo -e "\nPasswords for authenticating to LDAP will NOT be included!"
		echo -e "You must enter passwords for LDAP in web app\n\n**********\n\n"
		osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Very important info regarding LDAP Servers:" & return & "" & return & "Passwords for authenticating to LDAP will NOT be included!" & return & "" & return & "These must be set manually in JSS."  buttons {"Continue"} default button "Continue" with icon caution' -e 'end timeout'
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"						
				xml_file=$(xml ed -d "/$xmlNode/connection/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
				validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
				if [[ $validate_xml == "valid" ]]; then
					echo "Successfully edited $resourceXML"
				else
					echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
					mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
					echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
				fi
				xml_count=$(( $xml_count + 1 ))	
			done
elif [ "$jssResource" = "directorybindings" ]
	then
		xmlNodeName
		echo -e "\n**********\n\nVery Important Info regarding Directory Bindings -- "
		echo -e "\nPasswords for directory binding account will NOT be included!"
		echo -e "You must set these passwords for LDAP in web app\n\n**********\n\n"
		osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Very important info regarding Directory Bindings:" & return & "" & return & "Passwords for directory binding account will NOT be included!" & return & "" & return & "These must be set manually in JSS."  buttons {"Continue"} default button "Continue" with icon caution' -e 'end timeout'
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"						
				xml_file=$(xml ed -d "/$xmlNode/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
				validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
				if [[ $validate_xml == "valid" ]]; then
					echo "Successfully edited $resourceXML"
				else
					echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
					mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
					echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
				fi	
				xml_count=$(( $xml_count + 1 ))			
			done
elif [ "$jssResource" = "packages" ]
	then
		xmlNodeName
		# for packages with no category assigned we need to strip the category element from the xml or it will fail to upload.
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"						
				if [[ `grep "No category assigned" <"$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML` ]]; then 
					echo "Stripping category string from $resourceXML"
					xml_file=$(xml ed -d "/$xmlNode/id" -d "/$xmlNode/category" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
						mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi		
				else
					category=$(xpath '//category[1]/text()' < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML  2>/dev/null)
					category_upper=$(echo "$category" | tr [a-z] [A-Z])
					xml_file=$(xml ed -d "/$xmlNode/id" -u "/package/category" -v "$category_upper"  "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					updateIDs				
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
						mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi
				fi
				if [[ $id_update_error == "YES" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
				fi
				xml_count=$(( $xml_count + 1 ))		
			done
elif [ "$jssResource" = "osxconfigurationprofiles" ]
	then
		xmlNodeName
		# Groups must be migrated first,
		scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfConfigProfiles to do shell script "echo '"${totalFetchedIDs}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfConfigProfiles &" " & jssResource &" were found. Do you want to keep the computers in the scope?" & return & "" & return & "Keeping the computers will increase the time it takes to edit the xmls drastically as each id will need to be updated." & return & "" & return & "What do you want to do?" buttons {"Remove Computers", "Keep Computers"} with icon caution' -e 'button returned of result' -e 'end timeout')"
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"	
				category=$(xpath '//general/category/name[1]/text()' < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML  2>/dev/null)
				category_upper=$(echo "$category" | tr [a-z] [A-Z])
				
				if [ -f /tmp/selfserv_category_ids.txt ]; then
					rm /tmp/selfserv_category_ids.txt
				fi
				if [ -f /tmp/selfserv_categories.txt ]; then
					rm /tmp/selfserv_categories.txt
				fi
								
				xpath /"$xmlNodeName"/self_service/self_service_categories/category < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML | grep 'name' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' > /tmp/selfserv_categories.txt
				xpath /"$xmlNodeName"/self_service/self_service_categories/category < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML | grep 'id' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' > /tmp/selfserv_category_ids.txt
				echo "Changing category names to upper case"
				while read -r line; do
					selfserv_uppercase_cat=$(echo "$line" | tr [a-z] [A-Z])
					selfserv_cat_array+=("$selfserv_uppercase_cat")
				done <"/tmp/selfserv_categories.txt"
					
				xml_file=$(cat "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				i=0
				while read -r line; do
					xml_file=$(echo "$xml_file" | xml ed -u "//self_service_categories/category[id='$line']/name[1]/text()" -v "${selfserv_cat_array[i]}")
					echo "${selfserv_cat_array[i]} changed to upper case"
					i=$(( $i + 1 ))
				done <"/tmp/selfserv_category_ids.txt"
					
				unset selfserv_cat_array
				rm /tmp/selfserv_category_ids.txt
				rm /tmp/selfserv_categories.txt	
									
				# edit the xml to strip out the id and add the site and correct category id
				if [[ $scopeChoice == "Keep Computers" ]]; then
					xml_file=$(xml ed -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" -u "//general/category/name" -v "$category_upper" -d "/$xmlNode/general/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				else
					xml_file=$(xml ed -d "//computers" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" -u "//general/category/name" -v "$category_upper" -d "/$xmlNode/general/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				fi	
				
				updateIDs				
				echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
				validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
				if [[ $validate_xml == "valid" ]]; then
					echo "Successfully edited $resourceXML"
				else
					echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
					mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
					echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
				fi
				if [[ $id_update_error == "YES" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
				fi	
				xml_count=$(( $xml_count + 1 ))	
			done
elif [ "$jssResource" = "restrictedsoftware" ]
	then
		xmlNodeName	
		osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Very important info regarding Restricted Software:" & return & "" & return & "It is critical that the following items are migrated first:" & return & "" & return & "1. Computer Groups" & return & "2. Buildings" & return & "3. Departments" buttons {"Cancel", "Continue"} default button "Continue" with icon caution' -e 'end timeout'
		if (( $? == 0 )); then
			scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfConfigProfiles to do shell script "echo '"${totalFetchedIDs}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfConfigProfiles &" " & jssResource &" were found. Do you want to keep  scope?" & return & "" & return & "Keeping the scope will increase the time it takes to edit the xmls drastically as each id will need to be updated." & return & "" & return & "What do you want to do?" buttons {"Remove Scope", "Keep Scope"} with icon caution' -e 'button returned of result' -e 'end timeout')"
			for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
				do
					echo "Editing $resourceXML "
					xml_to_update="$resourceXML"
					# we don't want restriced software to be site specific so we will remove the site			
					if [[ $scopeChoice == "Keep Scope" ]]; then
						xml_file=$(xml ed  -d "/$xmlNode/general/id" -d "/$xmlNode/general/site" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					else
						xml_file=$(xml ed -d "//scope"  -d "/$xmlNode/general/id" -d "/$xmlNode/general/site" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					fi					
					updateIDs				
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
						mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi
					if [[ $id_update_error == "YES" ]]; then
						mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
					fi
					xml_count=$(( $xml_count + 1 ))		
				done
		else
			echo "User cancelled"
			exit 0
		fi								
elif [ "$jssResource" = "policies" ]
	then
		xmlNodeName
		# One off polices created by casper remote will not be included
		# self service icons will not be included
		osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Very important info regarding Policies:" & return & "" & return & "1. One-off policies generated by Casper Remote will not be included" & return & "" & return & "2. Self Service icons will not be migrated, they must be added manually via the JSS" buttons {"Continue"} default button "Continue" with icon caution' -e 'end timeout'
		scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfConfigProfiles to do shell script "echo '"${totalFetchedIDs}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfConfigProfiles &" " & jssResource &" were found. Do you want to keep the computers in the scope?" & return & "" & return & "Keeping the computers will increase the time it takes to edit the xmls drastically as each id will need to be updated." & return & "" & return & "What do you want to do?" buttons {"Remove Computers", "Keep Computers"} with icon caution' -e 'button returned of result' -e 'end timeout')"
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"						
				# we don't want to copy one off casper remote policies so a couple of checks will be made to weed them out.
				# one off polices are named similar to this <name>2016-03-08 at 12:58 PM | alan.mccrossen | 1 Computer</name>
				policy_name="$(xpath '/policy/general/name[1]/text()' <"$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML 2>/dev/null)"
				# one off policies have no category assigned
				# if the policy name follows the one off policy format and has no category assigned we will assume it's a one off policy and skip it.
				if [[ $(grep "<name>No category assigned</name>" <"$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML) ]] && [[ $policy_name == *"| "*" |"* ]]; then
					echo "Policy $resourceXML is a one off policy.  Ignoring..."
					# rename the skipped polices so we can go back and check them if needed
					mv "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML "$localOutputDirectory"/"$jssResource"/fetched_xml/skipped_$resourceXML
				else
					echo "$resourceXML is not a one off policy"
					category=$(xpath '//general/category/name[1]/text()' < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML  2>/dev/null)
					category_upper=$(echo "$category" | tr [a-z] [A-Z])
					
					if [ -f /tmp/selfserv_category_ids.txt ]; then
						rm /tmp/selfserv_category_ids.txt
					fi
					if [ -f /tmp/selfserv_categories.txt ]; then
						rm /tmp/selfserv_categories.txt
					fi
					
					xpath /"$xmlNodeName"/self_service/self_service_categories/category < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML | grep 'name' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' > /tmp/selfserv_categories.txt
					xpath /"$xmlNodeName"/self_service/self_service_categories/category < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML | grep 'id' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' > /tmp/selfserv_category_ids.txt
					echo "Changing category names to upper case"
					while read -r line; do
						selfserv_uppercase_cat=$(echo "$line" | tr [a-z] [A-Z])
						selfserv_cat_array+=("$selfserv_uppercase_cat")
					done <"/tmp/selfserv_categories.txt"
					
					xml_file=$(cat "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					i=0
					while read -r line; do
						echo "Updating $line"
						xml_file=$(echo "$xml_file" | xml ed -u "//self_service_categories/category[id='$line']/name[1]/text()" -v "${selfserv_cat_array[i]}")
						i=$(( $i + 1 ))
					done <"/tmp/selfserv_category_ids.txt"
					
					unset selfserv_cat_array
					rm /tmp/selfserv_category_ids.txt
					rm /tmp/selfserv_categories.txt				
					
					# remove the id and self service icon element, change the site and add the correct id for the general category					
					if [[ $scopeChoice == "Keep Computers" ]]; then
						echo "keeping computers in scope"
						xml_file=$(echo "$xml_file" | xml ed -d "/$xmlNode/general/id" -d "/$xmlNode/self_service/self_service_icon" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" -u "//general/category/name" -v "$category_upper")						
					else
						echo "removing computers from scope"
						xml_file=$(xml ed -d "//computers" -d "/$xmlNode/general/id" -d "/$xmlNode/self_service/self_service_icon" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" -u "//general/category/name" -v "$category_upper" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)		
					fi
												
					# if there is any deferral set for the policy it can cause the resource to fail to post if the time is in the past so it will be stripped out					
					deferral=$(echo $xml_file | xpath "/policy/user_interaction/allow_deferral_until_utc[1]/text()" 2>/dev/null)
					if [[ ! $deferral == "" ]]; then
						echo "Stripping policy deferral details from xml"
						echo "$xml_to_update - Stripping policy deferral details from xml" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log					
						xml_file=$(echo $xml_file | xml ed -d "/policy/user_interaction/allow_deferral_until_utc")
					fi
					updateIDs
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
						mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi
					if [[ $id_update_error == "YES" ]]; then
						mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
					fi									
				fi
				xml_count=$(( $xml_count + 1 ))
			done
elif [ "$jssResource" = "managedpreferenceprofiles" ]
	then
	xmlNodeName
			scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfConfigProfiles to do shell script "echo '"${totalFetchedIDs}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfConfigProfiles &" " & jssResource &" were found. Do you want to keep the computers in the scope?" & return & "" & return & "Keeping the computers will increase the time it takes to edit the xmls drastically as each id will need to be updated." & return & "" & return & "What do you want to do?" buttons {"Remove Computers", "Keep Computers"} with icon caution' -e 'button returned of result' -e 'end timeout')"
			for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
				do
					echo "Editing $resourceXML "
					xml_to_update="$resourceXML"
					
					if [[ $scopeChoice == "Keep Computers" ]]; then
						xml_file=$(xml ed  -d "/$xmlNode/general/id" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					else
						xml_file=$(xml ed -d "//computers"  -d "/$xmlNode/general/id" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					fi										
																
					updateIDs				
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
						mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi
					if [[ $id_update_error == "YES" ]]; then
						mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
					fi
					xml_count=$(( $xml_count + 1 ))		
				done	
elif [ "$jssResource" = "macapplications" ]
	then
		xmlNodeName
		# the category id has to be updated
		scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfConfigProfiles to do shell script "echo '"${totalFetchedIDs}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfConfigProfiles &" " & jssResource &" were found. Do you want to keep the computers in the scope?" & return & "" & return & "Keeping the computers will increase the time it takes to edit the xmls drastically as each id will need to be updated." & return & "" & return & "What do you want to do?" buttons {"Remove Computers", "Keep Computers"} with icon caution' -e 'button returned of result' -e 'end timeout')"
		for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
			do
				echo "Editing $resourceXML "
				xml_to_update="$resourceXML"
				category=$(xpath '//general/category/name[1]/text()' < "$localOutputDirectory"/"$jssResource"/fetched_xml  2>/dev/null)
				category_upper=$(echo "$category" | tr [a-z] [A-Z])
				selfservice_category=$(xpath '//self_service_categories/category/name[1]/text()' < "$localOutputDirectory"/"$jssResource"/fetched_xml  2>/dev/null)
				selfservice_category_upper=$(echo "$selfservice_category" | tr [a-z] [A-Z])
				
				if [[ $scopeChoice == "Keep Computers" ]]; then
					xml_file=$(xml ed -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" -u "//general/category/name" -v "$category_upper" -u "//self_service_categories/category/name" -v "$selfservice_category_upper" -d "/$xmlNode/general/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				else
					xml_file=$(xml ed -d "//computers" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" -u "//general/category/name" -v "$category_upper" -u "//self_service_categories/category/name" -v "$selfservice_category_upper" -d "/$xmlNode/general/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
				fi										
										
				updateIDs				
				echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
				validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
				if [[ $validate_xml == "valid" ]]; then
					echo "Successfully edited $resourceXML"
				else
					echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
					mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
					echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
				fi
				if [[ $id_update_error == "YES" ]]; then
					mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
				fi	
				xml_count=$(( $xml_count + 1 ))	
			done
elif [ "$jssResource" = "licensedsoftware" ]
	then
	xmlNodeName
	# the licensed software xml's only contain the computer ids and not the name so we will strip out that whole section.
	echo "For $jssResource we will strip out the computers, as machines recon in the new jss this will fill back up"
			for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
				do
					echo "Editing $resourceXML "
					xml_to_update="$resourceXML"						
					xml_file=$(xml ed -d "/$xmlNode/computers"  -d "/$xmlNode/general/id" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
						mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 					
					fi
					xml_count=$(( $xml_count + 1 ))
				done
elif [ "$jssResource" = "computerconfigurations" ] || [ "$jssResource" = "peripheraltypes" ]
	then
	xmlNodeName
	# These resources have a slightly different xml structure
	echo "For $jssResource - no need for extra special Editing.  Simply removing references to ID's and add the site"
			for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
				do
					echo "Editing $resourceXML "
					xml_to_update="$resourceXML"						
					xml_file=$(xml ed -d "/$xmlNode/general/id" -u "/$xmlNode/general/site/id" -v "$new_site_id" -u "/$xmlNode/general/site/name" -v "$new_site_name" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
					echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
					validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
					if [[ $validate_xml == "valid" ]]; then
						echo "Successfully edited $resourceXML"
					else
						echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
						mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
						echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
					fi
					xml_count=$(( $xml_count + 1 ))
				done
elif [ "$jssResource" = "advancedcomputersearches" ]
	then
	xmlNodeName
	scopeChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set numberOfGroups to do shell script "echo '"${totalFetchedIDs}"'"' -e 'Tell application "System Events" to display dialog "" & numberOfGroups &" " & jssResource &" were found. Do you want to keep the computers in the scope?" & return & "" & return & "Keeping the computers will increase the time it takes to edit the xmls drastically as each id will need to be updated." & return & "" & return & "What do you want to do?" buttons {"Remove Computers", "Keep Computers"} with icon caution' -e 'button returned of result' -e 'end timeout')"
	echo "For $jssResource - no need for extra special Editing.  Simply removing references to ID's and add the site"
	for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
		do
			echo "Editing $resourceXML "
			xml_to_update="$resourceXML"
			if [[ $scopeChoice == "Remove Computers" ]]; then
				echo "removing computers from scope"
				xml_file=$(xml ed -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" -d "/$xmlNode/id" -d "//computers" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
			elif [[ $scopeChoice == "Keep Computers" ]]; then		
				echo "keeping computers in scope"
				xml_file=$(xml ed -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" -d "/$xmlNode/id" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
			fi								
			updateIDs				
			echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
			validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
			if [[ $validate_xml == "valid" ]]; then
				echo "Successfully edited $resourceXML"
			else
				echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
				mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
				echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
			fi
			if [[ $id_update_error == "YES" ]]; then
				mv "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_update_id/edited_"$resourceXML"
			fi	
			xml_count=$(( $xml_count + 1 ))	
		done
else
	xmlNodeName
	echo "For $jssResource - no need for extra special Editing.  Simply removing references to ID's and add the site"
	for resourceXML in $(ls "$localOutputDirectory"/"$jssResource"/fetched_xml)
		do
			echo "Editing $resourceXML "
			xml_to_update="$resourceXML"	
			if [ "$jssResource" = "printers" ] || [ "$jssResource" = "scripts" ]; then
				category=$(xpath '//category[1]/text()' < "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML 2>/dev/null)
				category_upper=$(echo "$category" | tr [a-z] [A-Z])
				xml_file=$(xml ed -d "/$xmlNode/id" -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name"  -u "//category" -v "$category_upper" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)	
			else					
				xml_file=$(xml ed -d "/$xmlNode/id" -u "/$xmlNode/site/id" -v "$new_site_id" -u "/$xmlNode/site/name" -v "$new_site_name" "$localOutputDirectory"/"$jssResource"/fetched_xml/$resourceXML)
			fi	
			echo "$xml_file" > "$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" 
			validate_xml="$(xml val $localOutputDirectory/$jssResource/edited_xml/edited_$resourceXML | awk '{print $NF}')"					
			if [[ $validate_xml == "valid" ]]; then
				echo "Successfully edited $resourceXML"
			else
				echo "Failed to edit $resourceXML, moving to failed_to_edit directory"
				mv	"$localOutputDirectory"/"$jssResource"/edited_xml/edited_"$resourceXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_edit/edited_"$resourceXML"
				echo "$resourceXML - Failed to edit the xml: validation failed" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
			fi
			xml_count=$(( $xml_count + 1 ))
		done		
fi

if [ $number_of_id_update_errors -gt 0 ]; then
	errorButton="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'set NumberOfErrors to do shell script "echo '"${number_of_id_update_errors}"'"' -e 'set localOutputDirectory to do shell script "echo '"${localOutputDirectory}"'"' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'Tell application "System Events" to display dialog "There were " & NumberOfErrors & " errors updating IDs for " & jssResource & "." & return & "" & return & " The xmls that failed can be found in " & localOutputDirectory & "/" & jssResource & "/failed_xml/failed_to_update_id" & return & "" & return & "" & jssResource & "_error.log is also in that location which will have more info on what went wrong." buttons {"Exit", "Continue", "Open error.log"} default button "Open error.log" with icon caution' -e 'button returned of result' -e 'end timeout')"
	if [[ $errorButton == "Exit" ]]; then
		echo "User chose to exit"
		exit 1
	elif [[ $errorButton == "Open error.log" ]]; then
		echo "opening error.log"
		open "$localOutputDirectory/$jssResource/failed_xml/_"$jssResource"_error.log"
		sleep 3
		buttonReturned="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "What do you want to do?" buttons {"Exit", "Try Again", "Continue"} default button {"Continue"} with icon caution' -e 'button returned of result' -e 'end timeout')"
		if [[ $buttonReturned == "Exit" ]]; then
			echo "User chose to exit"
			exit 1
		else
			echo "User chose to continue"
		fi		
	else
		echo "User chose to continue"
	fi
fi

}

##########################################################################################

updateIDs()
{
ids_to_get_file=/tmp/ids_to_get.txt

resource_list="$(ls $localOutputDirectory | grep -v health_check | grep -v authentication_check | grep -v duplicate_name_check | grep -v new_ids | grep -v archives | grep -v .DS_Store)"
# get the current jssResource and xml node so we can change back to it when we are done
xml_jssResource="$jssResource"
xml_xmlNode="$xmlNode"

for jssResource in $resource_list; do
	update_count=1
	echo -e "\n**********\n**********"
	echo "xml file resource is: $xml_jssResource"
	echo "resource to update is: $jssResource"
	# the xml nodes are different depending on wether you are in the xml for a given resource or updating a element in a different resource.
	# for example in a computer extension attribute xml the node is computer_extension_attribute but in a computer xml it is extension_attribute
	# a variable is set to yes so that the xmlNodeName function knows node name to use

	# for computers we are going to use the serial number to get the new id rather that the computer name, there is less chance of this failing as the serial numbers are constant in their format
	updating_ids=YES 
	xmlNodeName
	echo "node is: $xmlNode"
	echo -e "\n\n\n"
	#make sure nothing is left in the array or variables after last run
	unset ids_to_get
	unset ids_to_change_array
	new_id=""
	resource_to_find=""
	gen_cat=""
	selfserv_cat=""
	id_update_error=NO
	
	if [[ $xml_jssResource == computers ]] && [[ $jssResource == printers ]]; then
		echo "Printer nodes in computers don't have an id so no need to update these"
		continue
	fi
	if [[ $xml_jssResource == computers ]] && [[ $jssResource == licensedsoftware ]]; then
		echo "Licensed software nodes in computers don't have an id so no need to update these"
		continue
	fi

	if [[ $xml_jssResource == $jssResource ]]; then
		echo "$xml_jssResource is the resource we are working on so it will be skipped"
		continue
	fi
	
	echo -e "\nChecking for any $jssResource ids that need to be edited for $xml_to_update\n"
	
	# for computers we want to use the udid and not the name, except for computer groups which dont have a udid field so we have to use the serial number
	if [[ $jssResource == "computers" ]]; then
		if [[ $xml_jssResource == "computergroups" ]]; then
			echo "$xml_file" | xml sel -t -m //"$xmlNode" -v serial_number -n > "$ids_to_get_file"
		else
			echo "$xml_file" | xml sel -t -m //"$xmlNode" -v udid -n > "$ids_to_get_file"
		fi
	# policies and config profiles have the general category and then self service categories so they have to be handled differently so that they are all changed
	elif [[ $xml_jssResource == "policies" ]] || [[ $xml_jssResource == "osxconfigurationprofiles" ]] && [[ $jssResource == "categories" ]]; then
		echo "CATEGORY id update for $xml_jssResource"
		gen_cat=$(echo "$xml_file" | xpath /"$xmlNodeName"/general/category | grep 'name' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}')
		echo "$gen_cat" > $ids_to_get_file
		echo "$xml_file" | xpath /"$xmlNodeName"/self_service/self_service_categories/category | grep 'name' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' > /tmp/selfserv_categories_to_change.txt
		cat /tmp/selfserv_categories_to_change.txt
		while read -r line; do
			echo "looking for $line"
			if grep "$line" $ids_to_get_file; then
				echo "Skipping $line, it is already in on the list"
			else	
				echo "adding $line to array"
    			echo "$line" >> $ids_to_get_file
    		fi	
		done < /tmp/selfserv_categories_to_change.txt
	else
		echo "$xml_file" | xml sel -t -m //"$xmlNode" -v name -n > "$ids_to_get_file"
	fi

	# add each item to an array, excluding any empty lines
	while read -r line; do
		if [[ ! "$line" == "" ]]; then
    		ids_to_change_array+=("$line")
		fi	
	done <"$ids_to_get_file"

	number_of_ids="${#ids_to_change_array[@]}"
	echo "Number of $jssResource ids to change: $number_of_ids"
	
	if [ $number_of_ids -eq 0 ]; then
		#rm "$ids_to_get_file"
		echo -e "\nDone with $jssResource for $xml_to_update\n\n"
		updating_ids=NO	
		continue
	fi

	# loop through the array and update each id
	for item in "${ids_to_change_array[@]}"; do
		echo "Updating $update_count of $number_of_ids $jssResource ids for $xml_jssResource $xml_to_update.....Processing $xml_count of $number_of_xmls xmls"
		# as we are stripping the current ids out so that they get new ones from the jss we don't want this to run on the type of resource we are working on.
		# for example if the reource xml is for a computer we don't want to try and update the computer ID
		# it will not be able to find the new id and cause ID element and name to be stripped out and cause the post to fail.
		if [[ $jssResource == "$xml_jssResource" ]]; then
			echo -e "\n$jssResource is the same type of resource we are working on so it will be skipped"
			continue
		fi

		echo -e "\n\n\n"		
		resource_to_find=$(echo $item)
		# a , is added to the beginning and end of the grep so that we get the correct match. In testing some resources had a name that contained a string that could be found in another resource name
		# this would return 2 ids and cause the post to fail. 
		# For example we have 2 EAs, 1 called CUDA Driver and another CUDA Driver Version, when the new id is checked for CUDA Driver it would return the required id along with the id for CUDA Driver version.
		# the new_ids.txt file is in the following format id,name,resource
		# so by searching by ",name," we only get the name we want
		new_id=$(grep -i ,"$resource_to_find", <"$localOutputDirectory/$jssResource"/new_id_list/"$jssResource"_new_ids.txt | awk -F, '{ print $1 }')
		echo -e "\n\n\n"
		echo "resource to find: $resource_to_find - new id: $new_id"
		if [[ $new_id == "" ]]; then
			echo -e "\n**Cannot get ID for $resource_to_find**\n**Stripping it from $xml_to_update**"
			if [[ $jssResource == "computers" ]]; then
				if [[ $xml_jssResource == "computergroups" ]]; then
					xml_file=$(echo "$xml_file" | xml ed -d "//$xmlNode[serial_number='$resource_to_find']")
				else
					xml_file=$(echo "$xml_file" | xml ed -d "//$xmlNode[udid='$resource_to_find']")
				fi
			else					
				xml_file=$(echo "$xml_file" | xml ed -d "//$xmlNode[name='$resource_to_find']")
			fi	
			echo "$xml_to_update - ID Update error: ($xmlNode) $resource_to_find stripped from xml" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log 
		else
			# for computers we are looking for the udid, or serial number for computer groups, not the name
			if [[ $jssResource == "computers" ]]; then
				if [[ $xml_jssResource == "computergroups" ]]; then
					xml_file=$(echo "$xml_file" | xml ed -u "//$xmlNode[serial_number='$resource_to_find']/id" -v "$new_id")
				else
					xml_file=$(echo "$xml_file" | xml ed -u "//$xmlNode[udid='$resource_to_find']/id" -v "$new_id")
				fi
			elif [[ $jssResource == "categories" ]]; then
				resource_to_find=$(echo "$resource_to_find" | tr [a-z] [A-Z])
				xml_file=$(echo "$xml_file" | xml ed -u "//$xmlNode[name='$resource_to_find']/id" -v "$new_id")
			else
				xml_file=$(echo "$xml_file" | xml ed -u "//$xmlNode[name='$resource_to_find']/id" -v "$new_id")		
			fi
			
			# get the id from the xml so that we can check it has successfully updated
			if [[ $jssResource == "categories" ]]; then
				if [[ $xml_jssResource == "policies" ]] || [[ $xml_jssResource == "osxconfigurationprofiles" ]]; then
					gen_category=$(echo "$xml_file" | xpath "//general/category/name[1]/text()")
					# if the general category is the category we are looking for check it's been updated
					if [[ $gen_category == "$resource_to_find" ]]; then
						check_general_category=$(echo "$xml_file" | xpath "//general/category[name='$resource_to_find']/id[1]/text()")
						if [[ ! $check_general_category == "$new_id" ]]; then
							echo -e "\n***Error: Failed to update general category for $resource_to_find in $xml_to_update***\n"
							echo "$xml_to_update - ID Update error: ($xmlNode) failed to update general category for $resource_to_find id to $new_id" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log
							# set this to NO so that the check isn't run again
							id_update_error=YES
							number_of_id_update_errors=$(( $number_of_id_update_errors + 1 ))
						else
							echo -e "successfully updated the category id for $resource_to_find\n"	
						fi
						
						echo "$xml_file" | xpath /"$xmlNodeName"/self_service/self_service_categories/category | grep 'name' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' > /tmp/selfserv_categories.txt
						if grep -q "$resource_to_find" /tmp/selfserv_categories.txt; then						
							check_selfservice_category=$(echo "$xml_file" | xpath "//self_service_categories/category[name='$resource_to_find']/id[1]/text()")
							if [[ ! $check_selfservice_category == "$new_id" ]]; then
								echo -e "\n***Error: Failed to update self service category for $resource_to_find in $xml_to_update***\n"
								echo "$xml_to_update - ID Update error: ($xmlNode) failed to update self service category for $resource_to_find id to $new_id" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log
								# set this to NO so that the check isn't run again
								id_update_error=YES
								number_of_id_update_errors=$(( $number_of_id_update_errors + 1 ))
							else
								echo -e "successfully updated the self service category id for $resource_to_find\n"	
							fi
							rm /tmp/selfserv_categories.txt
						fi	
					else	
						echo "$xml_file" | xpath /"$xmlNodeName"/self_service/self_service_categories/category | grep 'name' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' > /tmp/selfserv_categories.txt
						if grep -q "$resource_to_find" /tmp/selfserv_categories.txt; then
							check_selfservice_category=$(echo "$xml_file" | xpath "//self_service_categories/category[name='$resource_to_find']/id[1]/text()")				
							if [[ ! $check_selfservice_category == "$new_id" ]]; then
								echo -e "\n***Error: Failed to update self service category for $resource_to_find in $xml_to_update***\n"
								echo "$xml_to_update - ID Update error: ($xmlNode) failed to update self service category for $resource_to_find id to $new_id" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log
								# set this to NO so that the check isn't run again
								id_update_error=YES
								number_of_id_update_errors=$(( $number_of_id_update_errors + 1 ))
							else
								echo -e "successfully updated the self service category id for $resource_to_find\n"	
							fi
						fi	
					fi				
				else
					check_id=$(echo "$xml_file" | xpath "//$xmlNode[name='$resource_to_find']/id[1]/text()" 2>/dev/null)	
					if [[ ! $check_id == "$new_id" ]]; then
						echo -e "\n***Error: Failed to update $resource_to_find for $xml_to_update***\n"
						echo "$xml_to_update - ID Update error: ($xmlNode) failed to update $resource_to_find id to $new_id" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log
						id_update_error=YES
						number_of_id_update_errors=$(( $number_of_id_update_errors + 1 ))
					else
						echo -e "successfully updated id for $resource_to_find\n"
					fi	
				fi				
			elif [[ $jssResource == "computers" ]]; then
				if [[ $xml_jssResource == "computergroups" ]]; then
					check_id=$(echo "$xml_file" | xpath "//$xmlNode[serial_number='$resource_to_find']/id[1]/text()" 2>/dev/null)
					if [[ ! $check_id == "$new_id" ]]; then
						echo -e "\n***Error: Failed to update $resource_to_find for $xml_to_update***\n"
						echo "$xml_to_update - ID Update error: ($xmlNode) failed to update $resource_to_find id to $new_id" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log
						id_update_error=YES
						number_of_id_update_errors=$(( $number_of_id_update_errors + 1 ))
					else
						echo -e "successfully updated id for $resource_to_find\n"
					fi
				else
					check_id=$(echo "$xml_file" | xpath "//$xmlNode[udid='$resource_to_find']/id[1]/text()" 2>/dev/null)
					if [[ ! $check_id == "$new_id" ]]; then
						echo -e "\n***Error: Failed to update $resource_to_find for $xml_to_update***\n"
						echo "$xml_to_update - ID Update error: ($xmlNode) failed to update $resource_to_find id to $new_id" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log
						id_update_error=YES
						number_of_id_update_errors=$(( $number_of_id_update_errors + 1 ))
					else
						echo -e "successfully updated id for $resource_to_find\n"
						fi
				fi
			else
				check_id=$(echo "$xml_file" | xpath "//$xmlNode[name='$resource_to_find']/id[1]/text()" 2>/dev/null)
				if [[ ! $check_id == "$new_id" ]]; then
					echo -e "\n***Error: Failed to update $resource_to_find for $xml_to_update***\n"
					echo "$xml_to_update - ID Update error: ($xmlNode) failed to update $resource_to_find id to $new_id" >> "$localOutputDirectory"/"$xml_jssResource"/failed_xml/_"$xml_jssResource"_error.log
					id_update_error=YES
					number_of_id_update_errors=$(( $number_of_id_update_errors + 1 ))
				else
					echo -e "successfully updated id for $resource_to_find\n"
				fi
			fi
			echo -e "\n\n\n"
		fi

		update_count=$(( $update_count + 1 ))
	done	
	rm "$ids_to_get_file"
	echo -e "\nDone with $jssResource for $xml_to_update\n\n"
	updating_ids=NO	
done
# switch back to the original resource
jssResource="$xml_jssResource"
xmlNode="$xml_xmlNode"

}

##########################################################################################

postResource ()
{

echo -e "\n\nTime to finally post $jssResource to destination JSS...\n\n"
osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set newjss to do shell script "echo '"${newjss}"'"' -e 'Tell application "System Events" to display dialog "Time to post " & jssResource &"" buttons {"Exit", "Continue"} cancel button "Exit" default button "Continue"' -e 'end timeout'
if [ ! $? -eq 0 ]; then
	echo "User chose to quit"
	exit 0
fi	
sleep 1
if [ $jssResource = "accounts" ]
	then
		echo "For accounts, we need to post users first, then groups..."
		echo -e "\n\n----------\nPosting users...\n"
		sleep 1
		totalEditedResourceXML_user=$(ls "$localOutputDirectory"/"$jssResource"/edited_xml/edited_user* | wc -l | sed -e 's/^[ \t]*//')
		postInt_user=0	
		for editedXML_user in $(ls "$localOutputDirectory"/"$jssResource"/edited_xml/edited_user*)
		do
			curlError=""
			authError=""
			contentError=""
			notfoundError=""
			newResourceIDerror=""
			failed_resource=""

			let "postInt_user = $postInt_user + 1"
			echo -e "\n----------\n----------"
			echo -e "\nPosting $jssResource...$editedXML_user ( $postInt_user out of $totalEditedResourceXML_user ) \n"
	 		curl -k "$newjss"/JSSResource/accounts/userid/0 --user "${new_jss_apiuser}":"${new_jss_apipass}" -H "Accept: application/xml" -X POST -T "$editedXML_user" > /tmp/postoutput
			curlError=$(grep "Error" </tmp/postoutput | sed 's#.*<p>\(.*\)</p>*#\1#')
			authError=$(grep "authentication" </tmp/postoutput)
			contentError=$(grep "Content is not allowed" </tmp/postoutput)
			notfoundError=$(grep "The server has not found anything matching the request URI" </tmp/postoutput)
			if [[ ! "$curlError" == "" ]] || [[ ! "$authError" == "" ]] || [[ ! "$contentError" == "" ]] || [[ ! "$notfoundError" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to post $editedXML_user $failed_resource***\n\n"
				mv "$editedXML_user" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_upload/edited_userResult$postInt_user.xml
				echo "$editedXML_user - ${curlError} ${authError} ${contentError} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			elif [[ ! "$newResourceIDerror" == "" ]]; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to get new id $editedXML_user ***\n\n"
				mv "$editedXML_user" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_get_id/edited_userResult$postInt_user.xml
				echo "$editedXML_user - ${curlError} ${authError} ${contentError} ${newResourceIDerror} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			else
				echo "Successfully posted $editedXML_user"
				mv "$editedXML_user" "$localOutputDirectory"/"$jssResource"/completed_xml/edited_userResult$postInt_user.xml
			fi
			rm /tmp/postoutput
			
		done		
		echo -e "\n\n----------\nPosting groups...\n"
		sleep 1
		totalEditedResourceXML_group=$(ls "$localOutputDirectory"/"$jssResource"/edited_xml/edited_group* | wc -l | sed -e 's/^[ \t]*//')
		postInt_group=0	
		for editedXML_group in $(ls "$localOutputDirectory"/"$jssResource"/edited_xml/edited_group*)
		do
			curlError=""
			authError=""
			contentError=""
			notfoundError=""
			newResourceIDerror=""
			failed_resource=""
			
			let "postInt_group = $postInt_group + 1"
			echo -e "\n----------\n----------"
			echo -e "\nPosting $jssResource...$editedXML_group ( $postInt_group out of $totalEditedResourceXML_group ) \n"
	 		curl -k "$newjss/JSSResource/accounts/groupid/0" --user "${new_jss_apiuser}":"${new_jss_apipass}" -H "Accept: application/xml" -X POST -T "$editedXML_group" > /tmp/postoutput
			curlError=$(grep "Error" </tmp/postoutput | sed 's#.*<p>\(.*\)</p>*#\1#')
			authError=$(grep "authentication" </tmp/postoutput)
			contentError=$(grep "Content is not allowed" </tmp/postoutput)
			notfoundError=$(grep "The server has not found anything matching the request URI" </tmp/postoutput)
			if [[ ! "$curlError" == "" ]] || [[ ! "$authError" == "" ]] || [[ ! "$contentError" == "" ]] || [[ ! "$notfoundError" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to post $editedXML_group ***\n\n"
				mv "$editedXML_group" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_upload/edited_groupResult$postInt_group.xml
				echo "$editedXML_group - ${curlError} ${authError} ${contentError} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			elif [[ ! "$newResourceIDerror" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to get new id $editedXML_group ***\n\n"
				mv "$editedXML_group" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_get_id/edited_groupResult$postInt_group.xml
				echo "$editedXML_group - ${curlError} ${authError} ${contentError} ${newResourceIDerror} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			else
				echo "Successfully posted $editedXML_group"
				mv "$editedXML_group" "$localOutputDirectory"/"$jssResource"/completed_xml/edited_groupResult$postInt_group.xml
			fi
			rm /tmp/postoutput			
		done				
elif [ $jssResource = "computergroups" ]
	then 
		# For computers we post static groups first as smart groups can contain static groups
		echo -e "\n\n----------\nPosting static computer groups...\n"
		totalEditedResourceXML_staticGroups=$(ls "$localOutputDirectory"/computergroups/edited_xml/static_group_edited* | wc -l | sed -e 's/^[ \t]*//')
		postInt_static=0	
		for editedXML_static in $(ls "$localOutputDirectory"/computergroups/edited_xml/static_group_edited*)
		do
			curlError=""
			authError=""
			contentError=""
			notfoundError=""
			newResourceIDerror=""
			failed_resource=""

			let "postInt_static = $postInt_static + 1"
			echo -e "\n----------\n----------"
			echo -e "\nPosting $jssResource...$editedXML_static ( $postInt_static out of $totalEditedResourceXML_staticGroups ) \n"
	 		curl -k "$newjss/JSSResource/computergroups/id/0" --user "${new_jss_apiuser}":"${new_jss_apipass}" -H "Accept: application/xml" -X POST -T "$editedXML_static" > /tmp/postoutput
			curlError=$(grep "Error" </tmp/postoutput | sed 's#.*<p>\(.*\)</p>*#\1#')
			authError=$(grep "authentication" </tmp/postoutput)		
			contentError=$(grep "Content is not allowed" </tmp/postoutput)
			notfoundError=$(grep "The server has not found anything matching the request URI" </tmp/postoutput)
			if [[ ! "$curlError" == "" ]] || [[ ! "$authError" == "" ]] || [[ ! "$contentError" == "" ]] || [[ ! "$notfoundError" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to post $editedXML_static ***\n\n"
				mv "$editedXML_static" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_upload/editedXML_static$postInt_static.xml
				echo "$editedXML_static - ${curlError} ${authError} ${contentError} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			elif [[ ! "$newResourceIDerror" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to get new id $editedXML_static ***\n\n"
				mv "$editedXML_static" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_get_id/editedXML_static$postInt_static.xml
				echo "$editedXML_static - ${curlError} ${authError} ${contentError} ${newResourceIDerror} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			else
				echo "Successfully posted $editedXML_static"
				mv "$editedXML_static" "$localOutputDirectory"/"$jssResource"/completed_xml/editedXML_static$postInt_smart.xml	
			fi
			rm /tmp/postoutput
		done
		echo -e "\n\n----------\nPosting smart computer groups...\n"
		sleep 1
		totalEditedResourceXML_smartGroups=$(ls "$localOutputDirectory"/computergroups/edited_xml/smart_group_edited* | wc -l | sed -e 's/^[ \t]*//')
		postInt_smart=0	
		for editedXML_smart in $(ls "$localOutputDirectory"/computergroups/edited_xml/smart_group_edited*)
		do
			curlError=""
			authError=""
			contentError=""
			notfoundError=""
			newResourceIDerror=""
			failed_resource=""

			let "postInt_smart = $postInt_smart + 1"
			echo -e "\n----------\n----------"
			echo -e "\nPosting $jssResource...$editedXML_smart ( $postInt_smart out of $totalEditedResourceXML_smartGroups ) \n"
	 		curl -k "$newjss/JSSResource/computergroups/id/0" --user "${new_jss_apiuser}":"${new_jss_apipass}" -H "Accept: application/xml" -X POST -T "$editedXML_smart" > /tmp/postoutput
			curlError=$(grep "Error" </tmp/postoutput | sed 's#.*<p>\(.*\)</p>*#\1#')
			authError=$(grep "authentication" </tmp/postoutput)
			contentError=$(grep "Content is not allowed" </tmp/postoutput)
			notfoundError=$(grep "The server has not found anything matching the request URI" </tmp/postoutput)
			if [[ ! "$curlError" == "" ]] || [[ ! "$authError" == "" ]] || [[ ! "$contentError" == "" ]] || [[ ! "$notfoundError" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to post $editedXML_smart ***\n\n"
				mv "$editedXML_smart" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_upload/editedXML_smart$postInt_smart.xml
				echo "$editedXML_smart - ${curlError} ${authError} ${contentError} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			elif [[ ! "$newResourceIDerror" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to get new id $editedXML_smart ***\n\n"
				mv "$editedXML_smart" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_get_id/editedXML_smart$postInt_smart.xml
				echo "$editedXML_smart - ${curlError} ${authError} ${contentError} ${newResourceIDerror} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			else
				echo "Successfully posted $editedXML_smart"
				mv "$editedXML_smart" "$localOutputDirectory"/"$jssResource"/completed_xml/editedXML_smart$postInt_smart.xml	
			fi
			rm /tmp/postoutput
		done
else

	totalEditedResourceXML=$(ls "$localOutputDirectory"/"$jssResource"/edited_xml | wc -l | sed -e 's/^[ \t]*//')
	postInt=0	
	for editedXML in $(ls "$localOutputDirectory"/"$jssResource"/edited_xml)
		do
			curlError=""
			authError=""
			contentError=""
			notfoundError=""
			newResourceIDerror=""
			failed_resource=""
			
			xmlPost=$(cat "$localOutputDirectory"/"$jssResource"/edited_xml/$editedXML)
			let "postInt = $postInt + 1"
			echo -e "\n----------\n----------"
			echo -e "\nPosting $jssResource...$editedXML ( $postInt out of $totalEditedResourceXML ) \n"
	 		curl -k "$newjss/JSSResource/$jssResource/id/0" --user "${new_jss_apiuser}":"${new_jss_apipass}" -H "Accept: application/xml" -X POST -T "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML" > /tmp/postoutput
			curlError=$(grep "Error" </tmp/postoutput | sed 's#.*<p>\(.*\)</p>*#\1#')
			authError=$(grep "authentication" </tmp/postoutput)
			contentError=$(grep "Content is not allowed" </tmp/postoutput)
			notfoundError=$(grep "The server has not found anything matching the request URI" </tmp/postoutput)
			if [[ ! "$curlError" == "" ]] || [[ ! "$authError" == "" ]] || [[ ! "$contentError" == "" ]] || [[ ! "$notfoundError" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to post $editedXML ***\n\n"
				echo -e "$resourceName\n\n"
				mv "$localOutputDirectory/$jssResource/edited_xml/$editedXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_upload/
				echo "$editedXML - ${curlError} ${authError} ${contentError} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			elif [[ ! "$newResourceIDerror" == "" ]] ; then
				failed_resource=$(xpath '//name[1]/text()' < "$localOutputDirectory"/"$jssResource"/edited_xml/"$editedXML_user" 2>/dev/null)
				echo -e "\n\n----------\n*** Failed to get new id $editedXML_smart ***\n\n"
				echo -e "$resourceName\n\n"
				mv "$localOutputDirectory/$jssResource/edited_xml/$editedXML" "$localOutputDirectory"/"$jssResource"/failed_xml/failed_to_get_id/
				echo "$editedXML - ${curlError} ${authError} ${contentError} ${newResourceIDerror} ${notfoundError} ${failed_resource}" >> "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log
			else
				echo "Successfully posted $editedXML"
				echo -e "$resourceName\n\n"
				mv "$localOutputDirectory/$jssResource/edited_xml/$editedXML" "$localOutputDirectory"/"$jssResource"/completed_xml/	
			fi
			rm /tmp/postoutput			
		done
		
fi
echo -e "\n\n**********\nPosting complete for $jssResource \n**********\n\n"

if [ -f "$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log ]; then
	NumberOfErrors=$(wc -l <"$localOutputDirectory"/"$jssResource"/failed_xml/_"$jssResource"_error.log | sed -e 's/^[ \t]*//')

	errorChoice="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'set NumberOfErrors to do shell script "echo '"${NumberOfErrors}"'"' -e 'set localOutputDirectory to do shell script "echo '"${localOutputDirectory}"'"' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'Tell application "System Events" to display dialog "There were " & NumberOfErrors & " errors posting " & jssResource & "." & return & "" & return & " The xmls that failed can be found in " & localOutputDirectory & "/" & jssResource & "/failed_xml" & return & "" & return & "" & jssResource & "_error.log is also in that location which will have more info on what went wrong." buttons {"Exit", "Continue", "Open error.log"} default button "Open error.log" with icon caution' -e 'button returned of result' -e 'end timeout')"
	if [[ $errorChoice == "Exit" ]]; then
		echo "User chose to exit"
		exit 1
	elif [[ $errorChoice == "Open error.log" ]]; then
		echo "opening error.log"
		open "$localOutputDirectory/$jssResource/failed_xml/_"$jssResource"_error.log"
		sleep 3
		buttonReturned="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "What do you want to do?" buttons {"Exit", "Try Again", "Continue"} default button {"Continue"} with icon caution' -e 'button returned of result' -e 'end timeout')"
		if [[ $buttonReturned == "Exit" ]]; then
			echo "User chose to exit"
			exit 1
		elif [[ $buttonReturned == "Try Again" ]]; then
			postResource
		else
			echo "User chose to continue"
		fi		
	else
		echo "User chose to continue"
	fi
else
	osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResourceReadable}"'"' -e 'set newjss to do shell script "echo '"${newjss}"'"' -e 'Tell application "System Events" to display dialog "" & jssResource &" successfully posted" buttons {"Continue"} default button "Continue"' -e 'end timeout'
fi
getNewIDs
}

###########################################################################################
getNewIDs ()
{
# we don't need the new ids for accounts or peripherals so we will skip them
if [[ ! $jssResource == "accounts" ]] && [[ ! $jssResource == "peripherals" ]]; then
	echo "wait 5 seconds so items post properly before getting new ids"
	sleep 5
	echo -e "\nGetting new ids for $jssResource\n"
	counter=1
	/usr/bin/curl -k -u "${new_jss_apiuser}":"${new_jss_apipass}" -H "Accept: application/xml" "${newjss}"/JSSResource/"${jssResource}" -X GET | xmllint --format - > "$localOutputDirectory"/"$jssResource"/new_id_list/"$jssResource"_new_ids.xml
	if [ ! $? -eq 0 ]; then
		echo "Error: Failed to download new ids for $jssResource"
		osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'Tell application "System Events" to display dialog "Failed to download new ids for " & jssResource &"." buttons {"Exit"} default button "Exit" with icon caution' -e 'end timeout'
		exit 1
	fi	

	Number=$(xpath "//size[1]/text()" <"$localOutputDirectory"/"$jssResource"/new_id_list/"$jssResource"_new_ids.xml 2>/dev/null)
	if [[ $Number == "" ]]; then
		echo "Error: failed to get number of new ids"
		osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'Tell application "System Events" to display dialog "Failed to get new ids for " & jssResource &"." buttons {"Exit"} default button "Exit" with icon caution' -e 'end timeout'
		exit 1
	fi
	
	if [[ $Number == "0" ]]; then
		no_ids_found=$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'Tell application "System Events" to display dialog "No new ids were found for " & jssResource &"." & return & "" & return & "If this is not correct you can try again to download them" buttons {"Continue","Try Again"} default button "Try Again" with icon caution' -e 'button returned of result' -e 'end timeout')
		if [[ $no_ids_found == "Try Again" ]]; then
			echo "No new ids found for $jssResource, checking again"
			getNewIDs
		else
			echo "No new ids found for $jssResource, skipping"	
		fi
	else		
	
		echo "Getting $Number new ids for $jssResource"

		while [ $counter -le $Number ]; do
			new_id=$(xpath "(//id)[$counter]/text()" <"$localOutputDirectory"/"$jssResource"/new_id_list/"$jssResource"_new_ids.xml 2>/dev/null)
			name=$(xpath "(//name)[$counter]/text()" <"$localOutputDirectory"/"$jssResource"/new_id_list/"$jssResource"_new_ids.xml 2>/dev/null)
			if  [ $jssResource = "computers" ]; then
				echo "$jssResource ($counter of $Number)"
				computer_serial_number="$(curl -k "$newjss"/JSSResource/computers/id/"$new_id" -H "Accept: application/xml" --user "${new_jss_apiuser}":"${new_jss_apipass}" | xpath "$xmlNode/general/serial_number[1]/text()" 2>/dev/null)"
				computer_udid="$(curl -k "$newjss"/JSSResource/computers/id/"$new_id" -H "Accept: application/xml" --user "${new_jss_apiuser}":"${new_jss_apipass}" | xpath "$xmlNode/general/udid[1]/text()" 2>/dev/null)"
				echo "$new_id - $name - $computer_serial_number - $computer_udid"
				echo "$new_id,$name,$computer_serial_number,$computer_udid," >> "$localOutputDirectory/$jssResource"/new_id_list/"$jssResource"_new_ids.txt
			else
				echo "$jssResource ($counter of $Number)"
				echo "$new_id - $name"
				echo "$new_id,$name," >> "$localOutputDirectory/$jssResource"/new_id_list/"$jssResource"_new_ids.txt
			fi
			counter=$(( $counter + 1 ))
		done
	fi	
else
	echo -e "\nWe don't need the new ids for $jssResource\n"
fi	
echo -e "\nDone with $jssResource"	
}
##########################################################################################

processResource ()
{
echo "---"
echo "Processing ${jssResourceReadable}"
ButtonPressed=$(osascript -e 'with timeout of 7200 seconds' -e 'set jssResourceReadable to do shell script "echo '"${jssResourceReadable}"'"' -e 'set the answer to the button returned of (display dialog "" & jssResourceReadable &"" buttons {"Exit", "Skip", "Continue"} default button "Continue")' -e 'end timeout')
if [[ $ButtonPressed == "Continue" ]]; then
	initializeDirectoriesPerResource
	setVariablesForResource
	createIDlist
	if [[ $failed == "YES" ]]; then
		echo "skipping $jssResourceReadable"
	else
		fetchResourceXML
		editResourceXML
		postResource
	fi	
elif [[ $ButtonPressed == "Exit" ]]; then
	echo "user chose to Exit"
	exit 0
elif [[ $ButtonPressed == "Skip" ]]; then
	echo "user chose to skip $jssResourceReadable"
fi
if [[ $manualResource == "YES" ]]; then
	manualRun
fi	
echo "---"
}

##########################################################################################

manualRun ()
{

jssResources="Categories
LDAP Servers
Accounts (JSS Admin Accounts and Groups)
Buildings
Departments
Extension Attributes (for computers)
Directory Bindings
Dock Items
Removable MAC Addresses
Printers
Licensed Software
Scripts
Netboot Servers
Computers
Distribution Points
Software Update Servers
Network Segments
Computer Groups
OS X Configuration Profiles
Restricted Software
Packages
Policies
Advanced Computer Searches
Managed Preferences
Configurations
Mac App Store Apps
Peripheral Types
Peripherals

Manual Upload"

resourceSelection=`/usr/bin/osascript <<-AppleScript
set siteListArray to (do shell script "echo '$jssResources'")
set {oldtid, AppleScript's text item delimiters} to {AppleScript's text item delimiters, return}
set siteList to every text item of siteListArray
tell application "System Events"
	activate
	set jssResource to choose from list siteList with prompt "Which JSS resource would you like to migrate?
	
	(WARNING - We strongly encourage you to proceed in order.)" OK button name {"Select"} cancel button name {"Exit"}
	if jssResource is false then
		return "Exit" as text
	else
		return jssResource
	end if
end tell
AppleScript`

echo "SELECTION IS $resourceSelection"
if [[ $resourceSelection == "Exit" ]]; then
	echo "User chose to exit"
	exit 0
elif [[ $resourceSelection == "Categories" ]]; then
	jssResource=categories
	jssResourceReadable="Categories"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "LDAP Servers" ]]; then	
	jssResource=ldapservers
	jssResourceReadable="LDAP Servers"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Accounts (JSS Admin Accounts and Groups)" ]]; then	
	jssResource=accounts
	jssResourceReadable="Accounts"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Buildings" ]]; then	
	jssResource=buildings
	jssResourceReadable="Buildings"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Departments" ]]; then	
	jssResource=departments
	jssResourceReadable="Departments"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Extension Attributes (for computers)" ]]; then	
	jssResource=computerextensionattributes
	jssResourceReadable="Computer Extension Attributes"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Directory Bindings" ]]; then	
	jssResource=directorybindings
	jssResourceReadable="Directory Bindings"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Dock Items" ]]; then	
	jssResource=dockitems
	jssResourceReadable="Dock Items"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Removable MAC Addresses" ]]; then	
	jssResource=removablemacaddresses
	jssResourceReadable="Removable Mac Addresses"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Printers" ]]; then	
	jssResource=printers
	jssResourceReadable="Printers"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Licensed Software" ]]; then	
	jssResource=licensedsoftware
	jssResourceReadable="Licensed Software"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Scripts" ]]; then	
	jssResource=scripts
	jssResourceReadable="Scripts"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Netboot Servers" ]]; then	
	jssResource=netbootservers
	jssResourceReadable="Netboot Servers"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Computers" ]]; then	
	jssResource=computers
	jssResourceReadable="Computers"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Distribution Points" ]]; then	
	jssResource=distributionpoints
	jssResourceReadable="Distribution Points"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Software Update Servers" ]]; then	
	jssResource=softwareupdateservers
	jssResourceReadable="Software Update Servers"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Network Segments" ]]; then	
	jssResource=networksegments
	jssResourceReadable="Network Segments"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Computer Groups" ]]; then	
	jssResource=computergroups
	jssResourceReadable="Computer Groups"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "OS X Configuration Profiles" ]]; then	
	jssResource=osxconfigurationprofiles
	jssResourceReadable="OS X Configuration Profiles"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Restricted Software" ]]; then	
	jssResource=restrictedsoftware
	jssResourceReadable="Restricted Software"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Packages" ]]; then	
	jssResource=packages
	jssResourceReadable="Packages"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Policies" ]]; then	
	jssResource=policies
	jssResourceReadable="Policies"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Advanced Computer Searches" ]]; then	
	jssResource=advancedcomputersearches
	jssResourceReadable="Advanced Computer Searches"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Managed Preferences" ]]; then	
	jssResource=managedpreferenceprofiles
	jssResourceReadable="Managed Preferences"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Configurations" ]]; then	
	jssResource=computerconfigurations
	jssResourceReadable="Configurations"
	getMigrationSite
	processResource
elif [[ $resourceSelection == "Mac App Store Apps" ]]; then	
	jssResource=macapplications
	jssResourceReadable="Mac App Store Apps"
	getMigrationSite
	processResource		
elif [[ $resourceSelection == "Peripheral Types" ]]; then	
	jssResource=peripheraltypes
	jssResourceReadable="Peripheral Types"
	getMigrationSite
	processResource		
elif [[ $resourceSelection == "Peripherals" ]]; then	
	jssResource=peripherals
	jssResourceReadable="Peripherals"
	getMigrationSite
	processResource		
elif [[ $resourceSelection == "Manual Upload" ]]; then
	jssResourceManualInput="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'tell application "System Events" to display dialog "You have chosen to specify XML files to upload to a given resource." & return & "" & return & "WARNING: Please only continue with this function if you know exactly what you are doing. No changes will be made to the xml(s)" & return & "" & return & "API Resource by name (e.g. computergroups) :" default answer "" buttons {"Back", "Continue"} cancel button "Back" default button "Continue"' -e 'text returned of result' -e 'end timeout')"
	if (( $? == 0 )); then
	
	curlError=""
	authError=""
	contentError=""
	gatewayError=""
	notfoundError=""
	newResourceIDerror=""

		echo "jssResource is $jssResourceManualInput"
		resultOutputDirectory="$(osascript -e 'tell application "System Events" to set myfolder to choose folder with prompt "Source directory containing XML files:"' -e 'return (posix path of myfolder)')"
		if [ ! $? -eq 0 ]; then
			exit 0
		fi	
		if [ -e "$resultOutputDirectory"/_"$jssResourceManualInput"_error.log ]; then
			mv "$resultOutputDirectory"/_"$jssResourceManualInput"_error.log "$resultOutputDirectory"/"$jssResourceManualInput"_error-`date +%Y%m%d%H%M%S`.log
		fi	
		echo "Source directory is: $resultOutputDirectory"
		actionChoice="$(osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Are you updating existing records (PUT) or creating new records (POST)?" buttons {"PUT", "POST"} default button "POST"' -e 'button returned of result' -e 'end timeout')"
		if [[ $actionChoice == "POST" ]]; then 
			echo "Proceeding to POST xml files..."
			curlAction="POST"
		elif [[ $actionChoice == "PUT" ]]; then 
			echo "Proceeding to PUT xml files..."
			curlAction="PUT"
		fi
		totalParsedResourceXML=$(ls "$resultOutputDirectory"$manualPost | wc -l | sed -e 's/^[ \t]*//')
		postInt=0
		for manualPost in $(ls "$resultOutputDirectory")  
			do 
				xmlPost=$(cat "$resultOutputDirectory"/$manualPost)
				let "postInt = $postInt + 1"
				if [[ ! $manualPost == "_"$jssResourceManualInput"_error.log" ]]; then 
					echo -e "\n----------\n----------"
					echo -e "\n$curlActionING $manualPost( $postInt out of $totalParsedResourceXML ) \n"
					curl -k "$newjss"/JSSResource/$jssResourceManualInput --user "${new_jss_apiuser}":"${new_jss_apipass}" -H "Content-Type: application/xml" -X "$curlAction" -d "$xmlPost" > /tmp/manualpostoutput		
					curlError=$(grep "Error" </tmp/manualpostoutput | sed 's#.*<p>\(.*\)</p>*#\1#')
					authError=$(grep "authentication" </tmp/manualpostoutput)
					gatewayError=$(grep "Timeout" </tmp/manualpostoutput)
					notfoundError=$(grep "The server has not found anything matching the request URI" </tmp/manualpostoutput)
					if [[ ! "$curlError" == "" ]] || [[ ! "$authError" == "" ]] || [[ ! "$gatewayError" == "" ]] || [[ ! "$newResourceIDerror" == "" ]] || [[ ! "$notfoundError" == "" ]]; then
						echo "$manualPost - ${curlError} ${authError} ${gatewayError} ${newResourceIDerror} ${notfoundError}" >> "$resultOutputDirectory"/_"$jssResourceManualInput"_error.log
						echo -e "\n\n----------\n*** Failed to $curlAction $manualPost ***\n\n"
					else
						echo "Successfully manualPost"
					fi	
					rm /tmp/manualpostoutput
				fi				
			done		 
	else
		manualRun
	fi
			
	if [ -f "$resultOutputDirectory"/_"$jssResourceManualInput"_error.log ]; then
		NumberOfErrors=$(wc -l <"$resultOutputDirectory"/_"$jssResourceManualInput"_error.log | sed -e 's/^[ \t]*//')

		errorChoice="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'set NumberOfErrors to do shell script "echo '"${NumberOfErrors}"'"' -e 'Tell application "System Events" to display dialog "There were " & NumberOfErrors & " errors" buttons {"Exit", "Open error.log"} default button "Open error.log" with icon caution' -e 'button returned of result' -e 'end timeout')"
		if [[ "$errorChoice" == "Exit" ]]; then
			echo "User chose to exit"
			exit 0
		elif [[ "$errorChoice" == "Open error.log" ]]; then
			echo "opening error.log"
			open "$resultOutputDirectory"/_"$jssResourceManualInput"_error.log
			exit 0
		fi
	else
			osascript -e 'with timeout of 7200 seconds' -e 'set curlAction to do shell script "echo '"${curlAction}"'"' -e 'Tell application "System Events" to display dialog "Successful " & curlAction &"" buttons {"Exit"} default button "Exit"' -e 'end timeout'
			exit 0
	fi	
else
	echo "That is not a valid selection...!"
	/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'tell application "System Events" to display dialog "That is not a valid selection!" buttons {"Back"} default button "Back" with icon caution' -e 'end timeout'
	manualRun
fi	
}

##########################################################################################

duplicateNameCheck()
{
number_of_duplicates=0

/usr/bin/curl -k -u "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" "${oldjss}"/JSSResource/$jssResource -X GET | xmllint --format - > "$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml
validate_xml="$(xml val "$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml | awk '{print $NF}')"					
if [[ ! $validate_xml == "valid" ]]; then
	button=$(/usr/bin/osascript  -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Failed to download a valid " & jssResource & " list xml from the source JSS!" buttons {"Exit", "Continue"} default button {"Exit"} with icon caution' -e 'button returned of result' -e 'end timeout')
	if [[ $button == "Exit" ]]; then
		exit 1
	fi
fi
	
awk -F'<name>|</name>' '/<name>/ {print $2}' "$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml > "$localOutputDirectory"/duplicate_name_check/source_"$jssResource".txt

# for computers we also want to check for duplicate serial numbers, mac address and UDIDs
if [[ "$jssResource" == "computers" ]]; then
	awk -F'<id>|</id>' '/<id>/ {print $2}' "$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml > "$localOutputDirectory"/duplicate_name_check/source_computers_ids.txt
	totalFetchedIDsComputers=$(wc -l <"$localOutputDirectory"/duplicate_name_check/source_computers_ids.txt | sed -e 's/^[ \t]*//')
	c=1
	for apiID in $(cat "$localOutputDirectory"/duplicate_name_check/source_computers_ids.txt)
		do
			echo "Getting serial number $c of $totalFetchedIDsComputers for source computers"
			curl -k "$oldjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "computer/general/serial_number[1]/text()" 2>/dev/null >> "$localOutputDirectory"/duplicate_name_check/source_computer_serialnumber.txt
			echo "" >> "$localOutputDirectory"/duplicate_name_check/source_computer_serialnumber.txt
			echo "Getting mac address $c of $totalFetchedIDsComputers for source computers"
			curl -k "$oldjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "computer/general/mac_address[1]/text()" 2>/dev/null >> "$localOutputDirectory"/duplicate_name_check/source_computer_macaddress.txt
			echo "" >> "$localOutputDirectory"/duplicate_name_check/source_computer_macaddress.txt
			echo "Getting udid $c of $totalFetchedIDsComputers for source computers"
			curl -k "$oldjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "computer/general/udid[1]/text()" 2>/dev/null >> "$localOutputDirectory"/duplicate_name_check/source_computer_udid.txt
			echo "" >> "$localOutputDirectory"/duplicate_name_check/source_computer_udid.txt
			c=$(( $c + 1 ))
		done
fi	
					
/usr/bin/curl -k -u "${new_jss_apiuser}":"${new_jss_apipass}" -H "Accept: application/xml" "${newjss}"/JSSResource/$jssResource -X GET | xmllint --format - > "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".xml
validate_xml="$(xml val "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".xml | awk '{print $NF}')"					
if [[ ! $validate_xml == "valid" ]]; then
	button=$(/usr/bin/osascript  -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Failed to download a valid " & jssResource & " list xml from the destination JSS!" buttons {"Exit", "Continue"} default button {"Exit"} with icon caution' -e 'button returned of result' -e 'end timeout')
	if [[ $button == "Exit" ]]; then
		exit 1
	fi
fi	
awk -F'<name>|</name>' '/<name>/ {print $2}' "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".xml > "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".txt

if [[ "$jssResource" == "computers" ]]; then
	duplicate_serials=0
	duplicate_macadd=0
	duplicate_udid=0
	awk -F'<id>|</id>' '/<id>/ {print $2}' "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".xml > "$localOutputDirectory"/duplicate_name_check/destination_computers_ids.txt
	totalFetchedIDsComputers=$(wc -l <"$localOutputDirectory"/duplicate_name_check/destination_computers_ids.txt | sed -e 's/^[ \t]*//')
	c=1
	for apiID in $(cat "$localOutputDirectory"/duplicate_name_check/destination_computers_ids.txt)
		do
			echo "Checking serial number $c of $totalFetchedIDsComputers"
			serialnumber=$(curl -k "$newjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${new_jss_apiuser}":"${new_jss_apipass}" | xpath "computer/general/serial_number[1]/text()" 2>/dev/null)
			duplicate=""       
  		 	duplicate=$(cat "$localOutputDirectory"/duplicate_name_check/source_computer_serialnumber.txt | grep -i "$serialnumber")
    		if [[ ! $duplicate == "" ]]; then
				echo "Duplicate computer serial number found: $serialnumber"
    			echo "Duplicate computer serial number: $serialnumber" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log
    			duplicate_serials=$(( $duplicate_serials + 1 ))
			fi
			
			echo "Checking mac address $c of $totalFetchedIDsComputers"
			macadd=$(curl -k "$newjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${new_jss_apiuser}":"${new_jss_apipass}" | xpath "computer/general/mac_address[1]/text()" 2>/dev/null)
			duplicate=""       
  		 	duplicate=$(cat "$localOutputDirectory"/duplicate_name_check/source_computer_macaddress.txt | grep -i "$macadd")
    		if [[ ! $duplicate == "" ]]; then
				echo "Duplicate computer mac address found: $macadd"
    			echo "Duplicate computer mac address: $macadd" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log
    			duplicate_macadd=$(( $duplicate_macadd + 1 ))
			fi
				
			echo "Checking $c of $totalFetchedIDsComputers udid"
			udid=$(curl -k "$newjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${new_jss_apiuser}":"${new_jss_apipass}" | xpath "computer/general/udid[1]/text()" 2>/dev/null)
			duplicate=""       
  		 	duplicate=$(cat "$localOutputDirectory"/duplicate_name_check/source_computer_udid.txt | grep -i "$udid")
    		if [[ ! $duplicate == "" ]]; then
				echo "Duplicate computer udid found: $udid"
    			echo "Duplicate computer udid: $udid" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log
    			duplicate_udid=$(( $duplicate_udid + 1 ))
			fi

			c=$(( $c + 1 ))
		done
		
		if [[ $duplicate_serials -gt 0 ]]; then
			echo -e "\ncomputer serial number:  $duplicate_serials" >> /tmp/number.of.duplicates.txt
			echo "these cannot be renamed and must be deleted from either the source or destination prior to migration" >> /tmp/number.of.duplicates.txt
			osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${duplicate_serials}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" duplicate computer serial numbers have been found." & return & "" & return & "These cannot be renamed and must be deleted from either the source or destination prior ro migrating" buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
			if [ ! $? -eq 0 ]; then
				echo "user chose to exit"
				exit 0
			fi
		fi

		if [[ $duplicate_macadd -gt 0 ]]; then
			echo -e "\ncomputer mac address:  $duplicate_macadd" >> /tmp/number.of.duplicates.txt
			echo "these cannot be renamed and must be deleted from either the source or destination prior to migration" >> /tmp/number.of.duplicates.txt
			osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${duplicate_macadd}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" duplicate computer macaddresses have been found." & return & "" & return & "These cannot be renamed and must be deleted from either the source or destination prior ro migrating" buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
			if [ ! $? -eq 0 ]; then
				echo "user chose to exit"
				exit 0
			fi
		fi

		if [[ $duplicate_udid -gt 0 ]]; then
			echo -e "\ncomputer udids:  $duplicate_udid" >> /tmp/number.of.duplicates.txt
			echo "these cannot be renamed and must be deleted from either the source or destination prior to migration" >> /tmp/number.of.duplicates.txt
			osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${duplicate_udid}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" duplicate computer udids have been found." & return & "" & return & "These cannot be renamed and must be deleted from either the source or destination prior ro migrating" buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
			if [ ! $? -eq 0 ]; then
				echo "user chose to exit"
				exit 0
			fi
		fi
		rm "$localOutputDirectory"/duplicate_name_check/source_computers_ids.txt "$localOutputDirectory"/duplicate_name_check/destination_computers_ids.txt	
fi

rm "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".xml


while read line           
do 
	xmlNodeName
	duplicate=""       
   	duplicate=$(cat "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".txt | grep -i "$line")
    	if [[ ! $duplicate == "" ]]; then
    		echo "Duplicate $jssResource: $line"
    		echo "Duplicate $jssResource: $line" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log
    		if [[ $jssResource == "accounts" ]]; then
    			id=$(xpath "//user[name='$line']/id[1]/text()" <"$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml 2>/dev/null)
    			account_type=userid
    			if [[ $jssResource == "" ]]; then
    				id=$(xpath "//group[name='$line']/id[1]/text()" <"$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml 2>/dev/null)
    				account_type=groupid
    			fi
    		elif [[ $jssResource == "restrictedsoftware" ]]; then
    			id=$(xpath "//restricted_software_title[name='$line']/id[1]/text()" <"$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml 2>/dev/null)
    		else		
    			id=$(xpath "//$xmlNode[name='$line']/id[1]/text()" <"$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml 2>/dev/null)
    		fi
    		if [[ $jssResource == "accounts" ]]; then
    			echo "$id,$line,$account_type" >> "$localOutputDirectory"/duplicate_name_check/duplicate_"$jssResource".txt
    		else		
    			echo "$id,$line" >> "$localOutputDirectory"/duplicate_name_check/duplicate_"$jssResource".txt
    		fi	
    	fi	
 		         
done <"$localOutputDirectory"/duplicate_name_check/source_"$jssResource".txt 

rm "$localOutputDirectory"/duplicate_name_check/source_"$jssResource".xml
rm "$localOutputDirectory"/duplicate_name_check/destination_"$jssResource".txt
rm "$localOutputDirectory"/duplicate_name_check/source_"$jssResource".txt

if [ -f "$localOutputDirectory"/duplicate_name_check/duplicate_"$jssResource".txt ]; then	
	number_of_duplicates=$(wc -l <"$localOutputDirectory"/duplicate_name_check/duplicate_"$jssResource".txt | sed -e 's/^[ \t]*//')
else
	number_of_duplicates=0
fi

if [[ $number_of_duplicates -gt 0 ]]; then
	echo -e "\n$jssResource:  $number_of_duplicates"  >> /tmp/number.of.duplicates.txt
	osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${number_of_duplicates}"'"' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" duplicate " & jssResource & " have been found." & return & "" & return & "Would you like to rename them now?" buttons {"Skip", "Rename"} cancel button "Skip" with icon caution' -e 'end timeout'
	if [ $? -eq 0 ]; then
		osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "This will write back to your source JSS!" & return & "" & return & "Are you sure?" buttons {"No", "Yes"} cancel button "No" with icon caution' -e 'end timeout'
		if [ $? -eq 0 ]; then
			if [ ! -d "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource" ]; then
				mkdir "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"
			fi
			upload_errors=0
			renamed=0	
			while read line; do
				echo "Line is: $line"
				apiID=$(echo $line | awk -F, '{print $1}')
				name=$(echo $line | awk -F, '{print $2}')
				if [[ $name == "$old_jss_apiuser" ]]; then
					echo "The name for $old_jss_apipass will  not be changed or the script will fail as the username we are using will be incorrect"
					echo "$jssResource: $old_jss_apiuser was not renamed" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log 
					skipped_account=1
					continue
				fi	
				new_name=$(echo "$name($apiID)")
				echo -e "\nDUPLICATE $jssResource: new name is $new_name"
				if [[ $jssResource == "accounts" ]]; then
					account_type=$(echo $line | awk -F, '{print $3}')
					xml=$(curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/$jssResource/"$account_type"/"$apiID")
				else
					xml=$(curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/$jssResource/id/"$apiID")
				fi
				xmlNodeName
				if [[ $jssResource == "ldapservers" ]]; then
					echo "$xml" | xml ed -u "/$xmlNode/connection/name" -v "$new_name" > "$localOutputDirectory"/"$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"/"$jssResource"_$apiID.xml
				elif [[ $jssResource == "licensedsoftware" ]] || [[ $jssResource == "computers" ]] || [[ $jssResource == "osxconfigurationprofiles" ]] || [[ $jssResource == "restrictedsoftware" ]] || [[ $jssResource == "policies" ]] || [[ $jssResource == "managedpreferenceprofiles" ]] || [[ $jssResource == "computerconfigurations" ]] || [[ $jssResource == "macapplications" ]]; then
					echo "$xml" | xml ed -u "/$xmlNode/general/name" -v "$new_name" > "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"/"$jssResource"_"$apiID".xml
				else
					echo "$xml" | xml ed -u "/$xmlNode/name" -v "$new_name" > "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"/"$jssResource"_"$apiID".xml
				fi
				validate_xml="$(xml val  "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"/"$jssResource"_"$apiID".xml | awk '{print $NF}')"					
				if [[ ! $validate_xml == "valid" ]]; then
					echo "****Error: Failed to edit the xml for $jssResource $name $apiID****"
					echo "Error: Failed to edit the xml for $jssResource $name $apiID" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log
					upload_errors=$(( $upload_errors + 1 ))
					continue
				fi	
						
				if [[ $jssResource == "accounts" ]]; then	
					curl -k "$oldjss"/JSSResource/"$jssResource"/"$account_type"/"$apiID" --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Content-Type: application/xml" -X "PUT" -T "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"/"$jssResource"_"$apiID".xml > /tmp/putoutput	
				else
					curl -k "$oldjss"/JSSResource/"$jssResource"/id/"$apiID" --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Content-Type: application/xml" -X "PUT" -T "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"/"$jssResource"_"$apiID".xml > /tmp/putoutput	
				fi
				putError=$(cat /tmp/putoutput | grep "Error" | grep "Not Found")
				if [[ ! $putError == "" ]]; then
					echo "****Error: Failed to upload "$jssResource"_"$apiID".xml****"
					echo "Error: Failed to upload "$jssResource"_"$apiID".xml" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log
					mv "$localOutputDirectory"/duplicate_name_check/renamed_"$jssResource"/"$jssResource"_"$apiID".xml/FAILED_"$jssResource"_"$apiID".xml
					upload_errors=$(( $upload_errors + 1 ))
				else	
					renamed=$(( $renamed + 1 ))	
					echo "$jssResource: $name renamed to $new_name" >> "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check.log
				fi
				putError=""
			done <"$localOutputDirectory"/duplicate_name_check/duplicate_"$jssResource".txt
			
			if [[ $skipped_account -gt 0 ]]; then
				echo "skipped:  $skipped_account ($name)"  >> /tmp/number.of.duplicates.txt
				skipped_account=0
			fi
			
			if [[ $renamed -gt 0 ]]; then
				echo "renamed:  $renamed"  >> /tmp/number.of.duplicates.txt
			fi
			if [[ $upload_errors -gt 0 ]]; then
				osascript -e 'with timeout of 7200 seconds' -e 'set fails to do shell script "echo '"${upload_errors}"'"' -e 'set jssResource to do shell script "echo '"${jssResource}"'"' -e 'Tell application "System Events" to display dialog "There were " & fails &" " & jssResource & " that we could not change the name for." & return & "" & return & "You can find out which ones by checking the _duplicate_name_check.log file." buttons {"OK"} default button "OK" with icon caution' -e 'end timeout'		
				echo "failed:  $upload_errors"  >> /tmp/number.of.duplicates.txt
			fi
		else
			echo -e "\nskipping renaming duplicate $jssResource\n"
			echo "skipped:  $number_of_duplicates"  >> /tmp/number.of.duplicates.txt
		fi
	else
		echo -e "\nskipping renaming duplicate $jssResource\n"
		echo "skipped:  $number_of_duplicates"  >> /tmp/number.of.duplicates.txt
	fi	
fi
}


##########################################################################################
# END OF FUNCTIONS
##########################################################################################
#SCRIPT
##########################################################################################
# Lets check the variables have been set
if [[ "$newjss" == "" ]]; then
	echo -e "\n\nError - new jss is not set\n\n"
	exit 1
else
	echo  "New JSS: ${newjss}"
fi

if [[ "$new_jss_apiuser" == "" ]]; then
	echo -e "\n\nError - new jss user is not set\n\n"
	exit 1
else
	echo  "New JSS user: ${new_jss_apiuser}"
fi

if [[ "$new_jss_apipass" == "" ]]; then
	echo -e "\n\nError - new jss password is not set\n\n"
	exit 1
else
	echo  "New JSS password: ${new_jss_apipass}"
fi

if [[ "$oldjss" == "" ]]; then
	echo -e "\n\nError - old JSS is not set\n\n"
	exit 1
else
	echo  "Old JSS: ${oldjss}"
fi

if [[ "$old_jss_apiuser" == "" ]]; then
	echo -e "\n\nError - old jss user is not set\n\n"
	exit 1
else
	echo  "Old JSS user: ${old_jss_apiuser}"
fi

if [[ "$new_jss_apipass" == "" ]]; then
	echo -e "\n\nError - old jss password is not set\n\n"
	exit 1
else
	echo  "Old JSS password: ${old_jss_apipass}"
fi

if [[ "$computer_management_pw" == "" ]]; then
	echo -e "\n\nError - computer management password is not set\n\n"
	exit 1
else
	echo "Computer management password: ${computer_management_pw}"
fi

if [[ "$localOutputDirectory" == "" ]]; then
	echo -e "\n\nError - local output directory is not set\n\n"
	exit 1
fi

# check we can write to the desired output location
echo -e "\nMaking sure we can write files to output directory..."
if [ -d $localOutputDirectory ]
	then
		echo "Output directory exists.  Making sure we can write files inside..."
			if [ -d "$localOutputDirectory"/authentication_check ]
				then 
					echo "Found previous authentication check directory.  Deleting..."
					rm -rf "$localOutputDirectory"/authentication_check 
					if (( $? == 0 )); then
						echo "Success."
					else 
						echo "Failure.  There is a problem with permissions in your output directory.  Aborting..."
						osascript -e 'with timeout of 7200 seconds' -e 'set outputDir to do shell script "echo '"${localOutputDirectory}"'"' -e 'Tell application "System Events" to display dialog "There is a problem with permissions in your output directory:" & return & "" & return & "" & outputDir &"" & return & "" & return & "Aborting!" buttons {"Exit"} default button "Exit" with icon caution' -e 'end timeout'
						exit 1
					fi
			fi
	else
		echo "Creating top level output directory..."
		mkdir "$localOutputDirectory"
			if (( $? == 0 ))
				then echo "Success."
				else 
					echo "Failure.  There is a problem with permissions in your output directory.  Aborting..."
					exit 1
			fi
		chmod 775 "$localOutputDirectory"
fi

echo "Creating authentication check directory..."
mkdir "$localOutputDirectory"/authentication_check 
chmod 775 "$localOutputDirectory"/authentication_check
		
echo -e "\n*****\nEverything looks good with your working directory\n*****\n"

osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Would you like to run a quick authentication check?" & return & "" & return & "This will entail creating a mock category in destination JSS and source JSS." buttons {"No", "Yes"} cancel button "No" default button "Yes" with title "Authentication Check"' -e 'end timeout'
if [ $? -eq 0 ]; then
	
	echo "Proceeding to test your credentials.  Downloading categories resource..."
	
	curl -k "$oldjss"/JSSResource/categories --user "${old_jss_apiuser}":"${old_jss_apipass}" > "$localOutputDirectory"/authentication_check/raw.xml
	curlStatus=$?
	
	if (( $curlStatus == 0 )); then
		echo -e "\nAble to communicate with $oldjss"
	else
		echo -e "\n\nUnable to communicate with $oldjss"
		echo "You may simply have a typo in your source JSS URL or there may be a network issue"
		echo -e "\n!!!!!!!!!!!!!!!!!!!!\nCURL ERROR - TERMINATING\n!!!!!!!!!!!!!!!!!!!!\n\n"
		osascript -e 'with timeout of 7200 seconds' -e 'set curlStatus to do shell script "echo '"${curlStatus}"'"' -e 'set oldjss to do shell script "echo '"${oldjss}"'"' -e 'Tell application "System Events" to display dialog "Unable to communicate with " & oldjss &"." & return & "" & return & "You may simply have a typo in your source JSS URL or there may be a network issue." & return & "" & return & "Curl Status: " & curlStatus &"" buttons {"Exit"} default button "Exit" with icon caution' -e 'end timeout'
		exit 1
	fi

	#Authentication checks
	if [[ $(grep "The request requires user authentication" <"$localOutputDirectory"/authentication_check/raw.xml) ]]; then
		echo -e "\nThere is a problem with your credentials for $oldjss\n"
		echo -e "\n!!!!!!!!!!!!!!!!!!!!\nAUTHENTICATION ERROR - TERMINATING\n!!!!!!!!!!!!!!!!!!!!\n\n"
		osascript -e 'with timeout of 7200 seconds' -e 'set oldjss to do shell script "echo '${oldjss}'"' -e 'Tell application "System Events" to display dialog "There is a problem with your credentials for:" & return & "" & return & "" & oldjss &"" & return & "" & return & "Aborting!" buttons {"Exit"} default button "Exit" with icon caution' -e 'end timeout'
		exit 1
	else 
		echo "Credentials check out for $oldjss"
	fi

	echo -e "\nTo check your API write access to $newjss \nwe will attempt to create a test category\n"
	echo "It will be named \"zzzz_Migration_Test_\", with a timestamp suffix"
	echo "Delete later if you wish"
	echo -e "\nAttempting post now...\n"
	curl -k "$newjss"/JSSResource/categories --user "${new_jss_apiuser}:${new_jss_apipass}" -H "Content-Type: application/xml" -X POST -d "<category><name>zzzz_Migration_Test_`date +%Y%m%d%H%M%S`</name><priority>20</priority></category>" > "$localOutputDirectory"/authentication_check/postCheck.xml
	curlStatus=$?
	
	if (( $curlStatus == 0 )); then
		echo -e "\nAble to communicate with $newjss"
	else
		echo -e "\n\nUnable to communicate with $newjss"
		echo "Please check exit status $curlStatus in curl documentation for more details"
		echo "You may simply have a typo in your destination JSS URL or there may be a network issue"
		echo -e "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\nCURL ERROR - TERMINATING\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n"
		osascript -e 'with timeout of 7200 seconds' -e 'set curlStatus to do shell script "echo '"${curlStatus}"'"' -e 'set newjss to do shell script "echo '"${newjss}"'"' -e 'Tell application "System Events" to display dialog "Unable to communicate with " & newjss &"." & return & "" & return & "You may simply have a typo in your source JSS URL or there may be a network issue." & return & "" & return & "Curl Status: " & curlStatus &"" buttons {"Exit"} default button "Exit" with icon caution' -e 'end timeout'
		exit 1
	fi

	if [[ $(grep "The request requires user authentication" <"$localOutputDirectory"/authentication_check/postCheck.xml) ]]; then
		echo -e "\nThere is a problem with your credentials for $newjss\n"
		echo -e "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\nAUTHENTICATION ERROR - TERMINATING\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n"
		osascript -e 'with timeout of 7200 seconds' -e 'set newjss to do shell script "echo '${newjss}'"' -e 'Tell application "System Events" to display dialog "There is a problem with your credentials for:" & return & "" & return & "" & newjss &"" & return & "" & return & "Aborting!" buttons {"Exit"} default button "Exit" with icon caution' -e 'end timeout'
		exit 1
	else 
		echo "Credentials check out for $newjss"
	fi
	
else
	echo "User chose to skip authentication check"
fi

# health check

osascript -e 'Tell application "System Events" to display dialog "Having certain resources with duplicate names or missing information in the source JSS could cause them or other items to fail to migrate." & return & "" & return & "It is recommended to run a health check first which will analyze your JSS and look for potential problems that should be addressed before migrating." & return & "" & return & "Do you want to run the health check now?" buttons {"No", "Yes"} cancel button "No" default button "Yes" with title "Health Check"'
if [ ! $? -eq 0 ]; then
	echo "User chose to skip health check"
else	
	echo "Creating health_check directory ..."
	if [ -d "$localOutputDirectory"/health_check ]
		then
			echo "Found existing directory -- Archiving..."
				if [ -d "$localOutputDirectory"/archives ]; then
				echo "Archive directory exists"
			else 
				echo "Archive directory does not exist.  Creating..."
				mkdir "$localOutputDirectory"/archives
			fi
		ditto -ck "$localOutputDirectory"/health_check "$localOutputDirectory"/archives/health_check-$(date +%Y%m%d%H%M%S).zip
		echo "Removing previous health_check directory"
		rm -rf "$localOutputDirectory"/health_check
	else
		echo "No previous health_check directory found"
	fi

	mkdir -p "$localOutputDirectory"/health_check

##### COMPUTERS #####
	/usr/bin/curl -k -u "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" "${oldjss}"/JSSResource/computers -X GET | xmllint --format - > "$localOutputDirectory"/health_check/ComputerList.xml
	validate_xml="$(xml val "$localOutputDirectory"/health_check/ComputerList.xml | awk '{print $NF}')"					
	if [[ ! $validate_xml == "valid" ]]; then
		button=$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Failed to download a valid Computer list xml!" buttons {"Exit", "Continue"} default button {"Exit"} with icon caution' -e 'button returned of result' -e 'end timeout')
		if [[ $button == "Exit" ]]; then
			exit 1
		fi
	fi	

	awk -F'<id>|</id>' '/<id>/ {print $2}' "$localOutputDirectory"/health_check/ComputerList.xml > "$localOutputDirectory"/health_check/computerplainlist.txt
	rm "$localOutputDirectory"/health_check/ComputerList.xml

	numberOfComputers=$(wc -l <"$localOutputDirectory"/health_check/computerplainlist.txt | sed -e 's/^[ \t]*//')
	i=1
	# for each computer we will get serial number,Mac Add,udid,name,id and send it to a text file
	for apiID in $(cat "$localOutputDirectory"/health_check/computerplainlist.txt)
		do
			echo -e "Getting serial number $i of $numberOfComputers\n"
			serial_number=$(curl -k "$oldjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "computer/general/serial_number[1]/text()" 2>/dev/null)
			echo -e "Getting computer name $i of $numberOfComputers\n"
			computer_name=$(curl -k "$oldjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "computer/general/name[1]/text()" 2>/dev/null)
			echo -e "Getting mac address $i of $numberOfComputers\n"
			macadd=$(curl -k "$oldjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "computer/general/mac_address[1]/text()" 2>/dev/null)		
			echo -e "Getting udid $i of $numberOfComputers\n"
			udid=$(curl -k "$oldjss"/JSSResource/computers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "computer/general/udid[1]/text()" 2>/dev/null)		
			echo "$serial_number,$macadd,$udid,$computer_name,$apiID" >> "$localOutputDirectory"/health_check/_ComputerInfoList.txt
			i=$(( $i + 1 ))
		done
	
	rm "$localOutputDirectory"/health_check/computerplainlist.txt

	# check for duplicates
	# grab all the serial numbers and put them into a variable
	# IFS needs to be changed to new line so that we don't get any weird name splits
	# then use grep to grab any lines from the ComputerInfoList file that have the serial number
	# this way we get all the info about the duplicates including id and not just the serial number
	# send the output to a file that
	duplicate_serial_numbers=$(awk -F, '{print $1}' "$localOutputDirectory"/health_check/_ComputerInfoList.txt | sort | uniq -d)
	echo -e "Duplicate Computer serial numbers:\n$duplicate_serial_numbers"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_serial_numbers;
		do
			# no need to worry about missing serials as they will be picked up by the missing serial number check
			if [[ "$item" == "Not Available" ]] || [[ "$item" == "" ]]; then
				continue
			fi
			grep "$item", <"$localOutputDirectory"/health_check/_ComputerInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_Computer_SerialNumbers.txt		
			done
	unset IFS

	
	duplicate_computer_macadd=$(awk -F, '{print $2}' "$localOutputDirectory"/health_check/_ComputerInfoList.txt | sort | uniq -d)
	echo -e "Duplicate Mac Addresses:\n$duplicate_computer_macadd"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_computer_macadd;
		do
			grep ,"$item", <"$localOutputDirectory"/health_check/_ComputerInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_Computer_MacAddresses.txt
		done
	unset IFS

	
	duplicate_computer_udids=$(awk -F, '{print $3}' "$localOutputDirectory"/health_check/_ComputerInfoList.txt | sort | uniq -d)
	echo -e "Duplicate udis:\n$duplicate_computer_udids"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_computer_udids;
		do
			grep ,"$item", <"$localOutputDirectory"/health_check/_ComputerInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_Computer_UDIDs.txt
		done
	unset IFS

	
	duplicate_computer_names=$(awk -F, '{print $4}' "$localOutputDirectory"/health_check/_ComputerInfoList.txt | sort | uniq -d)
	echo -e "Duplicate Computer Names:\n$duplicate_computer_names"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_computer_names;
		do
			# a "," is added before and after $item so that we don't get unwanted results added
			# for example there is a duplicate called MacBook Pro
			# without the leading "," we would get everything with "MacBook Pro" in the name that is not necessarily a duplicate, such as "admin's MacBook Pro"
			grep ,"$item", <"$localOutputDirectory"/health_check/_ComputerInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_Computer_Names.txt
		done
	unset IFS
	
	number_of_computer_name_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_Computer_Names.txt | sed -e 's/^[ \t]*//')
	if [[ $number_of_computer_name_dups -gt 0 ]]; then
		osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${number_of_computer_name_dups}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" duplicate computer names have been found." & return & "" & return & "Computers with duplicate names will failed to migrate to the new JSS. They can be renamed to fix this." & return & "" & return & "Would you like to rename them now? The computer JSS id will be added to the name and updated on the source JSS, for example ComputerName(999). " buttons {"Skip", "Rename"} cancel button "Skip" with icon caution' -e 'end timeout'
		if [ $? -eq 0 ]; then
			osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "This will write back to your source JSS!" & return & "" & return & "Are you sure?" buttons {"No", "Yes"} cancel button "No" with icon caution' -e 'end timeout'
			if [ $? -eq 0 ]; then
				mkdir "$localOutputDirectory"/health_check/renamed_computers
				echo "renaming computer name duplicates"
				computer_rename_errors=0
				while read -r line; do
					apiID=$(echo $line | awk -F, '{print $5}')
					computer_name=$(echo $line | awk -F, '{print $4}')
					new_computer_name="$computer_name($apiID)"
					echo -e "id is: $apiID"
					echo -e "name is: $computer_name"
					echo -e "new name is: $new_computer_name"
					computer_xml=$(curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/computers/id/"$apiID")
					echo "$computer_xml" | xml ed -u /computer/general/name -v "$new_computer_name" > "$localOutputDirectory"/health_check/renamed_computers/renamed_computer_$apiID.xml
					curl -k "$oldjss"/JSSResource/computers/id/"$apiID" --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Content-Type: application/xml" -X "PUT" -T "$localOutputDirectory"/health_check/renamed_computers/renamed_computer_"$apiID".xml > /tmp/putoutput
					putError=$(grep "Error" </tmp/putoutput)
					if [[ ! $putError == "" ]]; then
						echo "****Error: Failed to upload renamed_computer_$apiID.xml****"
						echo "Error: Failed to upload renamed_computer_$apiID.xml" >> "$localOutputDirectory"/health_check/_health_check.log
						mv "$localOutputDirectory"/health_check/renamed_computers/renamed_computer_"$apiID".xml "$localOutputDirectory"/health_check/renamed_computers/FAILED_computer_"$apiID".xml
						computer_rename_errors=$(( $computer_rename_errors + 1 ))	
					else		
						echo "Computer: $computer_name renamed to $new_computer_name" >> "$localOutputDirectory"/health_check/_health_check.log
					fi
					putError=""
				done <"$localOutputDirectory/health_check/duplicate_Computer_Names.txt"
				if [[ $computer_rename_errors -gt 0 ]]; then
					number_of_computer_name_dups=$computer_rename_errors
					osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${computer_rename_errors}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" renamed computers failed to upload to the source JSS" & return & "" & return & "You can find out which ones by checking the _health_check.log file." buttons {"OK"} default button "OK" with icon caution' -e 'end timeout'		
				else
					number_of_computer_name_dups=0
				fi
			else
				echo -e "\nskipping renaming duplicate computer names\n"	
			fi
		else
			echo -e "\nskipping renaming duplicate computer names\n"
		fi
	else
		number_of_computer_name_dups=0		
	fi

	# now lets check for any missing info, serial numbers, names, udids or mac address
	# if anything is missing send it to a text file
	while read -r line; do
		sernum="$(echo $line | awk -F, '{ print $1 }')"
		if [[ "$sernum" == "" ]] || [[ "$sernum" == "Not Available" ]]; then
			echo "$line" >> "$localOutputDirectory"/health_check/computers_with_no_serial.txt
		fi	
		macadd="$(echo $line | awk -F, '{ print $2 }')"
		if [[ "$macadd" == "" ]]; then
			echo "$line" >> "$localOutputDirectory"/health_check/computers_with_no_macaddress.txt
		fi	
		udid="$(echo $line | awk -F, '{ print $3 }')"
		if [[ "$udid" == "" ]]; then
			echo "$line" >> "$localOutputDirectory"/health_check/computers_with_no_udid.txt
		fi	
		name="$(echo $line | awk -F, '{ print $4 }')"
		if [[ "$name" == "" ]]; then
			echo "$line" >> "$localOutputDirectory"/health_check/computers_with_no_name.txt
		fi	
	done <"$localOutputDirectory/health_check/_ComputerInfoList.txt"

	
#### POLICIES #####
	/usr/bin/curl -k -u "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" "${oldjss}"/JSSResource/policies -X GET | xmllint --format - > "$localOutputDirectory"/health_check/PolicyList.xml
	validate_xml="$(xml val "$localOutputDirectory"/health_check/PolicyList.xml | awk '{print $NF}')"					
	if [[ ! $validate_xml == "valid" ]]; then
		button=$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Failed to download a valid Computer list xml!" buttons {"Exit", "Continue"} default button {"Exit"} with icon caution' -e 'button returned of result' -e 'end timeout')
		if [[ $button == "Exit" ]]; then
			exit 1
		fi
	fi	

	awk -F'<id>|</id>' '/<id>/ {print $2}' "$localOutputDirectory"/health_check/PolicyList.xml > "$localOutputDirectory"/health_check/policyplainlist.txt
	rm "$localOutputDirectory"/health_check/PolicyList.xml

	numberOfPolicies=$(wc -l <"$localOutputDirectory"/health_check/policyplainlist.txt | sed -e 's/^[ \t]*//')
	i=1
	# for each policy we will get name,id and send it to a text file
	for apiID in $(cat "$localOutputDirectory"/health_check/policyplainlist.txt)
		do
			echo -e "$i of $numberOfPolicies policies\n"
			policy_name=$(curl -k "$oldjss"/JSSResource/policies/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "policy/general/name[1]/text()" 2>/dev/null)
			# one off casper remote policies have a name like "2013-11-11 at 3:56 PM | alan.mccrossen | 1 Computer"
			# we don't care about these so we will skip them
			if [[ ! $policy_name == *"| "*"."*" |"* ]]; then		
				echo "$policy_name,$apiID" >> "$localOutputDirectory"/health_check/_PolicyInfoList.txt
			fi
			i=$(( $i + 1 ))	
		done
	rm "$localOutputDirectory"/health_check/policyplainlist.txt

	# check for any duplicates
	duplicate_policy_names=$(awk -F, '{print $1}' "$localOutputDirectory"/health_check/_PolicyInfoList.txt | sort | uniq -d)
	echo -e "Duplicate Policy Names:\n$duplicate_policy_names"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_policy_names;
		do
			grep "$item", <"$localOutputDirectory"/health_check/_PolicyInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_Policies.txt
		done
	unset IFS
	
	number_of_policy_name_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_Policies.txt | sed -e 's/^[ \t]*//')
	if [[ $number_of_policy_name_dups -gt 0 ]]; then
		osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${number_of_policy_name_dups}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" duplicate policy names have been found." & return & "" & return & "Policies with duplicate names will failed to migrate to the new JSS. They can be renamed to fix this." & return & "" & return & "Would you like to rename them now? The policy JSS id will be added to the name and updated on the source JSS, for example PolicyName(999). " buttons {"Skip", "Rename"} cancel button "Skip" with icon caution' -e 'end timeout'
		if [ $? -eq 0 ]; then
			osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "This will write back to your source JSS!" & return & "" & return & "Are you sure?" buttons {"No", "Yes"} cancel button "No" with icon caution' -e 'end timeout'
			if [ $? -eq 0 ]; then
				mkdir "$localOutputDirectory"/health_check/renamed_policies
				echo "renaming policy duplicates"
				policy_rename_errors=0
				while read -r line; do
					apiID=$(echo $line | awk -F, '{print $2}')
					policy_name=$(echo $line | awk -F, '{print $1}')
					new_policy_name="$policy_name($apiID)"
					echo -e "id is: $apiID"
					echo -e "name is: $policy_name"
					echo -e "new name is: $new_policy_name"
					policy_xml=$(curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/policies/id/"$apiID")
					echo "$policy_xml" | xml ed -u /policy/general/name -v "$new_policy_name" > "$localOutputDirectory"/health_check/renamed_policies/renamed_policy_$apiID.xml
					curl -k "$oldjss"/JSSResource/policies/id/"$apiID" --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Content-Type: application/xml" -X "PUT" -T "$localOutputDirectory"/health_check/renamed_policies/renamed_policy_"$apiID".xml > /tmp/putoutput
					putError=$(grep "Error" </tmp/putoutput)
					if [[ ! $putError == "" ]]; then
						echo "****Error: Failed to upload renamed_policy_$apiID.xml****"
						echo "Error: Failed to upload renamed_policy_$apiID.xml" >> "$localOutputDirectory"/health_check/_health_check.log
						mv "$localOutputDirectory"/health_check/renamed_policies/renamed_policy_"$apiID".xml "$localOutputDirectory"/health_check/renamed_policies/FAILED_policy_"$apiID".xml
						policy_rename_errors=$(( $policy_rename_errors + 1 ))
					else		
						echo "Policy: $policy_name renamed to $new_policy_name" >> "$localOutputDirectory"/health_check/_health_check.log
					fi
					putError=""
				done <"$localOutputDirectory/health_check/duplicate_Policies.txt"
				if [[ $policy_rename_errors -gt 0 ]]; then
					number_of_policy_name_dups=$policy_rename_errors
					osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${policy_rename_errors}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" renamed policies failed to upload to the source JSS" & return & "" & return & "You can find out which ones by checking the _health_check.log file." buttons {"OK"} default button "OK" with icon caution' -e 'end timeout'					
				else
					number_of_policy_name_dups=0
				fi
			else
				echo -e "\nskipping renaming duplicate policy names\n"
			fi	
		else
			echo -e "\nskipping renaming duplicate policy names\n"
		fi
	else
		number_of_policy_name_dups=0
	fi	

##### PRINTERS #####
	/usr/bin/curl -k -u "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" "${oldjss}"/JSSResource/printers -X GET | xmllint --format - > "$localOutputDirectory"/health_check/PrinterList.xml
	validate_xml="$(xml val "$localOutputDirectory"/health_check/PrinterList.xml | awk '{print $NF}')"					
	if [[ ! $validate_xml == "valid" ]]; then
		button=$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Failed to download a valid Computer list xml!" buttons {"Exit", "Continue"} default button {"Exit"} with icon caution' -e 'button returned of result' -e 'end timeout')
		if [[ $button == "Exit" ]]; then
			exit 1
		fi
	fi	

	awk -F'<id>|</id>' '/<id>/ {print $2}' "$localOutputDirectory"/health_check/PrinterList.xml > "$localOutputDirectory"/health_check/printerplainlist.txt
	rm "$localOutputDirectory"/health_check/PrinterList.xml

	numberOfPrinters=$(wc -l <"$localOutputDirectory"/health_check/printerplainlist.txt | sed -e 's/^[ \t]*//')
	i=1
	# for each printer we will get name,id and send it to a text file
	for apiID in $(cat "$localOutputDirectory"/health_check/printerplainlist.txt)
		do
			echo -e "$i of $numberOfPrinters printers\n"
			printer_name=$(curl -k "$oldjss"/JSSResource/printers/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "printer/name[1]/text()" 2>/dev/null)
			echo "$printer_name,$apiID" >> "$localOutputDirectory"/health_check/_PrinterInfoList.txt
			i=$(( $i + 1 ))	
		done
	rm "$localOutputDirectory"/health_check/printerplainlist.txt

	# check for duplicates
	duplicate_printer_names=$(awk -F, '{print $1}' "$localOutputDirectory"/health_check/_PrinterInfoList.txt | sort | uniq -d)
	echo -e "Duplicate Printer Names:\n$duplicate_printer_names"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_printer_names;
		do
			grep "$item", <"$localOutputDirectory"/health_check/_PrinterInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_Printers.txt
		done
	unset IFS

	number_of_printer_name_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_Printers.txt | sed -e 's/^[ \t]*//')
	if [[ $number_of_printer_name_dups -gt 0 ]]; then
		osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${number_of_printer_name_dups}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" duplicate printer names have been found." & return & "" & return & "Printers with duplicate names will failed to migrate to the new JSS. They can be renamed to fix this." & return & "" & return & "Would you like to rename them now? The printer JSS id will be added to the name and updated on the source JSS, for example PrinterName(999). " buttons {"Skip", "Rename"} cancel button "No" with icon caution' -e 'end timeout'
		if [ $? -eq 0 ]; then
			osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "This will write back to your source JSS!" & return & "" & return & "Are you sure?" buttons {"No", "Yes"} cancel button "No" with icon caution' -e 'end timeout'
			if [ $? -eq 0 ]; then
				mkdir "$localOutputDirectory"/health_check/renamed_printers
				echo "renaming printer duplicates"
				printer_rename_errors=0
				while read -r line; do	
					apiID=$(echo $line | awk -F, '{print $2}')
					printer_name=$(echo $line | awk -F, '{print $1}')
					new_printer_name="$printer_name($apiID)"
					echo -e "id is: $apiID"
					echo -e "name is: $printer_name"
					echo -e "new name is: $new_printer_name"
					printer_xml=$(curl --silent -k --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" -X GET  "$oldjss"/JSSResource/printers/id/"$apiID")
					echo "$printer_xml" | xml ed -u /printer/name -v "$new_printer_name" > "$localOutputDirectory"/health_check/renamed_printers/renamed_printer_$apiID.xml
					curl -k "$oldjss"/JSSResource/printers/id/"$apiID" --user "${old_jss_apiuser}":"${old_jss_apipass}" -H "Content-Type: application/xml" -X "PUT" -T "$localOutputDirectory"/health_check/renamed_printers/renamed_printer_"$apiID".xml > /tmp/putoutput
					if [[ ! $putError == "" ]]; then
						echo "****Error: Failed to upload renamed_printer_$apiID.xml****"
						echo "Error: Failed to upload renamed_printer_$apiID.xml" >> "$localOutputDirectory"/health_check/_health_check.log
						mv "$localOutputDirectory"/health_check/renamed_printers/renamed_printer_"$apiID".xml "$localOutputDirectory"/health_check/renamed_printers/FAILED_printer_"$apiID".xml
						printer_rename_errors=$(( $printer_rename_errors + 1 ))
					else		
						echo "Printer: $printer_name renamed to $new_printer_name" >> "$localOutputDirectory"/health_check/_health_check.log
					fi
					putError=""
				done <"$localOutputDirectory/health_check/duplicate_Printers.txt"
			
				if [[ $printer_rename_errors -gt 0 ]]; then
					number_of_printer_name_dups=$printer_rename_errors
					osascript -e 'with timeout of 7200 seconds' -e 'set duplicates to do shell script "echo '"${number_of_printer_name_dups}"'"' -e 'Tell application "System Events" to display dialog "" & duplicates &" renamed printers failed to upload to the source JSS" & return & "" & return & "You can find out which ones by checking the _health_check.log file." buttons {"OK"} default button "OK" with icon caution' -e 'end timeout'									
				else
					number_of_printer_name_dups=0
				fi	
			else
				echo -e "\nskipping renaming duplicate printer names\n"
			fi	
		else
			echo -e "\nskipping renaming duplicate printer names\n"
		fi
	else
		number_of_printer_name_dups=0	
	fi	

##### REMOVABLE MAC ADDRESSES #####
	/usr/bin/curl -k -u "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" "${oldjss}"/JSSResource/removablemacaddresses -X GET | xmllint --format - > "$localOutputDirectory"/health_check/RemovableMacAddressList.xml
	validate_xml="$(xml val "$localOutputDirectory"/health_check/RemovableMacAddressList.xml | awk '{print $NF}')"					
	if [[ ! $validate_xml == "valid" ]]; then
		button=$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Failed to download a valid Computer list xml!" buttons {"Exit", "Continue"} default button {"Exit"} with icon caution' -e 'button returned of result' -e 'end timeout')
		if [[ $button == "Exit" ]]; then
			exit 1
		fi
	fi	

	awk -F'<id>|</id>' '/<id>/ {print $2}' <"$localOutputDirectory"/health_check/RemovableMacAddressList.xml > "$localOutputDirectory"/health_check/removablemacaddressplainlist.txt
	rm "$localOutputDirectory"/health_check/RemovableMacAddressList.xml

	numberOfRemovableMacAddresses=$(wc -l <"$localOutputDirectory"/health_check/removablemacaddressplainlist.txt | sed -e 's/^[ \t]*//')
	i=1
	# for each printer we will get name,id and send it to a text file
	for apiID in $(cat "$localOutputDirectory"/health_check/removablemacaddressplainlist.txt)
		do
			echo -e "$i of $numberOfRemovableMacAddresses removable mac addresses\n"
			macaddress=$(curl -k "$oldjss"/JSSResource/removablemacaddresses/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "removable_mac_address/name[1]/text()" 2>/dev/null)
			echo "$macaddress,$apiID" >> "$localOutputDirectory"/health_check/_RemovableMacAddressInfoList.txt
			i=$(( $i + 1 ))	
		done
	rm "$localOutputDirectory"/health_check/removablemacaddressplainlist.txt

	# check for duplicates
	duplicate_addresses=$(awk -F, '{print $1}' "$localOutputDirectory"/health_check/_RemovableMacAddressInfoList.txt | sort | uniq -d)
	echo -e "Duplicate Mac Addresses:\n$duplicate_addresses"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_addresses;
		do
			grep "$item", <"$localOutputDirectory"/health_check/_RemovableMacAddressInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_removablemacaddresses.txt
		done
	unset IFS

##### PACKAGES #####
	/usr/bin/curl -k -u "${old_jss_apiuser}":"${old_jss_apipass}" -H "Accept: application/xml" "${oldjss}"/JSSResource/packages -X GET | xmllint --format - > "$localOutputDirectory"/health_check/Packages.xml
	validate_xml="$(xml val "$localOutputDirectory"/health_check/Packages.xml | awk '{print $NF}')"					
	if [[ ! $validate_xml == "valid" ]]; then
		button=$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "Failed to download a valid Computer list xml!" buttons {"Exit", "Continue"} default button {"Exit"} with icon caution' -e 'button returned of result' -e 'end timeout')
		if [[ $button == "Exit" ]]; then
			exit 1
		fi
	fi	

	awk -F'<id>|</id>' '/<id>/ {print $2}' <"$localOutputDirectory"/health_check/Packages.xml > "$localOutputDirectory"/health_check/packagesplainlist.txt
	rm "$localOutputDirectory"/health_check/Packages.xml

	numberOfPackages=$(wc -l <"$localOutputDirectory"/health_check/packagesplainlist.txt | sed -e 's/^[ \t]*//')
	i=1
	# for each printer we will get name,id and send it to a text file
	for apiID in $(cat "$localOutputDirectory"/health_check/packagesplainlist.txt)
		do
			echo -e "$i of $numberOfPackages packages\n"
			package_name=$(curl -k "$oldjss"/JSSResource/packages/id/"$apiID" -H "Accept: application/xml" --user "${old_jss_apiuser}":"${old_jss_apipass}" | xpath "package/name[1]/text()" 2>/dev/null)
			echo "$package_name,$apiID" >> "$localOutputDirectory"/health_check/_PackagesInfoList.txt
			i=$(( $i + 1 ))	
		done
	rm "$localOutputDirectory"/health_check/packagesplainlist.txt

	# check for duplicates
	duplicate_packages=$(awk -F, '{print $1}' "$localOutputDirectory"/health_check/_PackagesInfoList.txt | sort | uniq -d)
	echo -e "Duplicate Packages:\n$duplicate_packages"
	echo -e "\n\n"
	IFS=$'\n' 
	for item in $duplicate_packages;
		do
			grep "$item", <"$localOutputDirectory"/health_check/_PackagesInfoList.txt >> "$localOutputDirectory"/health_check/duplicate_packages.txt
		done
	unset IFS

####################
	# lets get the number of problems
	if [ -f "$localOutputDirectory"/health_check/computers_with_no_serial.txt ]; then
		number_of_computers_with_no_serial=$(wc -l <"$localOutputDirectory"/health_check/computers_with_no_serial.txt | sed -e 's/^[ \t]*//')
	else
		number_of_computers_with_no_serial=0
	fi	
	echo "$number_of_computers_with_no_serial computers with no serial number found"
	
	if [ -f "$localOutputDirectory"/health_check/computers_with_no_macaddress.txt ]; then
		number_of_computers_with_no_macadd=$(wc -l <"$localOutputDirectory"/health_check/computers_with_no_macaddress.tx | sed -e 's/^[ \t]*//')
	else
		number_of_computers_with_no_macadd=0
	fi
	echo "$number_of_computers_with_no_macadd computers with no mac address found"
	
	if [ -f "$localOutputDirectory"/health_check/computers_with_no_udid.txt ]; then
		number_of_computers_with_no_udid=$(wc -l <"$localOutputDirectory"/health_check/computers_with_no_udid.txt | sed -e 's/^[ \t]*//')
	else
		number_of_computers_with_no_udid=0
	fi	
	echo "$number_of_computers_with_no_udid computers with no udid found"
	
	if [ -f "$localOutputDirectory"/health_check/computers_with_no_name.txt ]; then
		number_of_computers_with_no_name=$(wc -l <"$localOutputDirectory"/health_check/computers_with_no_name.txt | sed -e 's/^[ \t]*//')
	else
		number_of_computers_with_no_name=0
	fi	
	echo "$number_of_computers_with_no_name computers with no name found"	
	
	if [ -f "$localOutputDirectory"/health_check/duplicate_Computer_SerialNumbers.txt ]; then
		number_of_serial_number_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_Computer_SerialNumbers.txt | sed -e 's/^[ \t]*//')
	else
		number_of_serial_number_dups=0
	fi
	echo "$number_of_serial_number_dups duplicate computer serial numbers found"		
	
	if [ -f "$localOutputDirectory"/health_check/duplicate_Computer_MacAddresses.txt ]; then
		number_of_macaddress_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_Computer_MacAddresses.txt | sed -e 's/^[ \t]*//')
	else
		number_of_macaddress_dups=0
	fi
	echo "$number_of_macaddress_dups duplicate computer mac addresses found"		
	
	if [ -f "$localOutputDirectory"/health_check/duplicate_Computer_UDIDs.txt ]; then
		number_of_udid_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_Computer_UDIDs.txt | sed -e 's/^[ \t]*//')
	else
		number_of_udid_dups=0
	fi
	
	if [ -f "$localOutputDirectory"/health_check/duplicate_removablemacaddresses.txt ]; then
		number_of_removablemacaddress_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_removablemacaddresses.txt | sed -e 's/^[ \t]*//')
	else
		number_of_removablemacaddress_dups=0
	fi

	if [ -f "$localOutputDirectory"/health_check/duplicate_packages.txt ]; then
		number_of_package_dups=$(wc -l <"$localOutputDirectory"/health_check/duplicate_packages.txt | sed -e 's/^[ \t]*//')
	else
		number_of_package_dups=0
	fi
	
	echo "$number_of_removablemacaddress_dups duplicate mac addresses found"
	
	echo "$number_of_udid_dups duplicate computer udids found"
			
	echo "$number_of_computer_name_dups duplicate computer names found"

	echo "$number_of_policy_name_dups duplicate policy names found"	
	
	echo "$number_of_printer_name_dups duplicate printer names found"
	
	echo "$number_of_package_dups duplicate packages names found"

	# if there are any potential problems inform the user
	if [ ! $number_of_computers_with_no_serial -eq 0 ] || [ ! $number_of_computers_with_no_macadd -eq 0 ] || [ ! $number_of_computers_with_no_udid -eq 0 ] || [ ! $number_of_computers_with_no_name -eq 0 ] || [ ! $number_of_serial_number_dups -eq 0 ] || [ ! $number_of_macaddress_dups -eq 0 ] || [ ! $number_of_udid_dups -eq 0 ] || [ ! $number_of_computer_name_dups -eq 0 ] || [ ! $number_of_policy_name_dups -eq 0 ] || [ ! $number_of_printer_name_dups -eq 0 ] || [ ! $number_of_removablemacaddress_dups -eq 0 ] || [ ! $number_of_package_dups -eq 0 ]; then
		button=$(osascript -e 'with timeout of 7200 seconds' -e 'set oldjss to do shell script "echo '"${oldjss}"'"' -e 'set noSerial to do shell script "echo '"${number_of_computers_with_no_serial}"'"' -e 'set noMacAdd to do shell script "echo '"${number_of_computers_with_no_macadd}"'"' -e 'set noUdid to do shell script "echo '"${number_of_computers_with_no_udid}"'"' -e 'set noName to do shell script "echo '"${number_of_computers_with_no_name}"'"' -e 'set SNdups to do shell script "echo '"${number_of_serial_number_dups}"'"' -e 'set MacAdddups to do shell script "echo '"${number_of_macaddress_dups}"'"' -e 'set UDIDdups to do shell script "echo '"${number_of_udid_dups}"'"' -e 'set CompNamedups to do shell script "echo '"${number_of_computer_name_dups}"'"' -e 'set PolicyDups to do shell script "echo '"${number_of_policy_name_dups}"'"' -e 'set PrinterDups to do shell script "echo '"${number_of_printer_name_dups}"'"' -e 'set RemovableMacAddDups to do shell script "echo '"${number_of_removablemacaddress_dups}"'"' -e 'set PackageDups to do shell script "echo '"${number_of_package_dups}"'"' -e 'Tell application "System Events" to display dialog "The following number of issues were found on " & oldjss &"" & return & "" & return & "Computers with no serial number:	" & noSerial &"" & return & "Computers with no UDID:			" & noUdid &"" & return & "Computers with no Mac address:	" & noMacAdd &"" & return & "Computers with no name:			" & noName &"" & return & "Computer serial number duplicates:	" & SNdups &"" & return & "Computer mac address duplicates:	" & MacAdddups &"" & return & "Computer UDID duplicates:			" & UDIDdups &"" & return & "Computer name duplicates:			" & CompNamedups &"" & return & "Policy name duplicates:			" & PolicyDups &"" & return & "Printer name duplicates:			" & PrinterDups &"" & return & "Removable Mac Address duplicates:	" & RemovableMacAddDups &"" & return & "Package duplicates:	" & PackageDups &"" & return & "" & return & "These need to be addressed or they could fail to migrate or cause other resources to fail." buttons {"Exit", "View Problems", "Continue"}' -e 'button returned of result' -e 'end timeout')
		if [[ $button == "Exit" ]]; then
			echo "User chose to exit"
			exit 0
		elif [[ $button == "View Problems" ]]; then
			open "$localOutputDirectory"/health_check
			open "$localOutputDirectory"/health_check/_health_check.log
			sleep 10
			buttonReturned="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'Tell application "System Events" to display dialog "What do you want to do?" buttons {"Exit", "Continue"} default button {"Continue"} with icon caution' -e 'button returned of result' -e 'end timeout')"
			if [[ $buttonReturned == "Exit" ]]; then
				exit 0
			fi	
		fi
	else
		osascript -e 'Tell application "System Events" to display dialog "Everything looks good!" buttons {"Continue"} default button "Continue" with title "Health Check"'
	fi	
fi

# compare source and destination JSS to check for duplicate names

osascript -e 'Tell application "System Events" to display dialog "Items will fail to migrate if an item with the same name is already on the destination JSS." & return & "" & return & "Renaming the item in your source JSS before migrating will prevent this. If any are found you can choose to rename them, the name will be changed to the current name followed by the jss id, for example PolicyName(999)." & return & "" & return & "Do you want to run the duplicate name check now?" buttons {"No", "Yes"} cancel button "No" default button "Yes" with title "Duplicate Name Check"'
if [ ! $? -eq 0 ]; then
	echo "User chose to skip duplicate name check"
else	
	echo "Creating duplicate_name_check directory ..."
	if [ -d "$localOutputDirectory"/duplicate_name_check ]; then
		echo "Found existing directory -- Archiving..."
		if [ -d "$localOutputDirectory"/archives ]; then
			echo "Archive directory exists"
		else 
			echo "Archive directory does not exist.  Creating..."
			mkdir "$localOutputDirectory"/archives
		fi
		ditto -ck "$localOutputDirectory"/duplicate_name_check "$localOutputDirectory"/archives/duplicate_name_check-$(date +%Y%m%d%H%M%S).zip
		echo "Removing previous duplicate_name_check directory"
		rm -rf "$localOutputDirectory"/duplicate_name_check
	else
		echo "No previous duplicate_name_check directory found"
	fi
	
	mkdir -p "$localOutputDirectory"/duplicate_name_check
	
	resources="categories ldapservers accounts buildings departments computerextensionattributes directorybindings dockitems removablemacaddresses printers licensedsoftware scripts netbootservers computers distributionpoints softwareupdateservers networksegments computergroups osxconfigurationprofiles restrictedsoftware packages policies advancedcomputersearches managedpreferenceprofiles computerconfigurations macapplications peripherals"
	
	if [ -f /tmp/number.of.duplicates.txt ]; then
		rm /tmp/number.of.duplicates.txt
	fi	
	
	i=0
	for item in $resources; do
		jssResource="$item"
		echo "checking for $jssResource duplicates"
		duplicateNameCheck
	done
	
	if [ -f /tmp/number.of.duplicates.txt ]; then
		osascript -e 'with timeout of 7200 seconds' -e 'set duplicate_log to POSIX file ("/tmp/number.of.duplicates.txt")' -e 'set duplicates to (read file duplicate_log)' -e 'Tell application "System Events" to display dialog "Number of duplicates:" & return & "" & return & "" & duplicates &"" buttons {"Exit", "Continue"} cancel button "Exit" with icon caution' -e 'end timeout'
		if [ ! $? -eq 0 ]; then
			echo "User chose to exit"
			mv /tmp/number.of.duplicates.txt "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check_summary.log
			exit 0
		fi
		mv /tmp/number.of.duplicates.txt "$localOutputDirectory"/duplicate_name_check/_duplicate_name_check_summary.log
	else		
		osascript -e 'Tell application "System Events" to display dialog "Everything looks good!" buttons {"Continue"} default button "Continue" with title "Duplicate Name Check"'
	fi	
fi	

# make sure none of the temp files are left from previous runs
if [ -f /tmp/postoutput ]; then
	rm /tmp/postoutput
fi	

if [ -f /tmp/putoutput ]; then
	rm /tmp/putoutput
fi	

if [ -f /tmp/manualpostoutput ]; then
	rm /tmp/manualpostoutput
fi	

# prompt if we want to automatically cycle through each resource in order or manually select a resource to run
runType="$(/usr/bin/osascript -e 'with timeout of 7200 seconds' -e 'tell application "System Events" to display dialog "Would you like to automatically cycle through each resource or select one manually to run?" buttons {"Manual", "Auto"} default button "Auto"' -e 'button returned of result' -e 'end timeout')"
if [[ $runType == "Manual" ]]; then
	manualResource=YES
	manualRun
else 
	manualResource=NO	
fi

getMigrationSite

jssResource=categories
jssResourceReadable="Categories"
processResource

jssResource=ldapservers
jssResourceReadable="LDAP Servers"
processResource

jssResource=accounts
jssResourceReadable="Accounts"
processResource

jssResource=buildings
jssResourceReadable="Buildings"
processResource

jssResource=departments
jssResourceReadable="Departments"
processResource

jssResource=computerextensionattributes
jssResourceReadable="Computer Extension Attributes"
processResource

jssResource=directorybindings
jssResourceReadable="Directory Bindings"
processResource

jssResource=dockitems
jssResourceReadable="Dock Items"
processResource

jssResource=removablemacaddresses
jssResourceReadable="Removable Mac Addresses"
processResource

jssResource=printers
jssResourceReadable="Printers"
processResource

jssResource=licensedsoftware
jssResourceReadable="Licensed Software"
processResource

jssResource=scripts
jssResourceReadable="Scripts"
processResource

jssResource=netbootservers
jssResourceReadable="Netboot Servers"
processResource

jssResource=computers
jssResourceReadable="Computers"
processResource

jssResource=distributionpoints
jssResourceReadable="Distribution Points"
processResource

jssResource=softwareupdateservers
jssResourceReadable="Software Update Servers"
processResource

jssResource=networksegments
jssResourceReadable="Network Segments"
processResource

jssResource=computergroups
jssResourceReadable="Computer Groups"
processResource

jssResource=osxconfigurationprofiles
jssResourceReadable="OS X Configuration Profiles"
processResource

jssResource=restrictedsoftware
jssResourceReadable="Restricted Software"
processResource

jssResource=packages
jssResourceReadable="Packages"
processResource

jssResource=policies
jssResourceReadable="Policies"
processResource

jssResource=advancedcomputersearches
jssResourceReadable="Advanced Computer Searches"
processResource

jssResource=managedpreferenceprofiles
jssResourceReadable="Managed Preferences"
processResource

jssResource=computerconfigurations
jssResourceReadable="Configurations"
processResource

jssResource=macapplications
jssResourceReadable="Mac App Store Apps"
processResource

jssResource=peripheraltypes
jssResourceReadable="Peripheral Types"
processResource

jssResource=peripherals
jssResourceReadable="Peripherals"
processResource

osascript -e 'Tell application "System Events" to display dialog "Done, beer time." buttons {"Exit"} default button "Exit"'
