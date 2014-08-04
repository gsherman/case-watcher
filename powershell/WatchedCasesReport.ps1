
$smtpServer="smtp.gmail.com"
$port = 587
$smtpLogin = "support@mycompany.com"
$smtpPassword = "password"
$from="Dovetail <support@mycompany.com>"

$BASEURL = "http://myserver/bootstrap/api/histories/case"		
$authToken = "mySecretAuthToken";
$agent5Url = "http://mycompany.com/agent5/"
$mailChimpApiKey="mySecretAuthToken";

$watchTag="watch";
$subject="Dovetail Watched Cases Report"	

$CRLF = "`r`n";

#$DebugPreference = "Stop" 						#powershell will show the message and then halt.
#$DebugPreference = "Inquire" 					#powershell will prompt the user.
#$DebugPreference = "SilentlyContinue" 			#powershell will not show the message. 
$DebugPreference = "Continue" 					#powershell will show the debug message.
			
#source other scripts
. .\DovetailCommonFunctions.ps1
. .\HtmlHelpers.ps1
. .\WatchedCasesCss.ps1

$css=css;

# don't run on Saturday or Sunday
# if Monday, look for activity since Friday (3 days ago)

if ((get-date).DayOfWeek -eq 'Saturday'){
	exit;	
}
if ((get-date).DayOfWeek -eq 'Sunday'){
	exit;	
}

$numberOfDaysAgo = 1;
if ((get-date).DayOfWeek -eq 'Monday'){
	$numberOfDaysAgo = 3;	
}
$timeAgo = (get-date).AddDays($numberOfDaysAgo * -1);


$ClarifyApplication = create-clarify-application; 
$ClarifySession = create-clarify-session $ClarifyApplication; 


function GetWatchers(){
	#get the list of distinct users
	$dataSet = new-object FChoice.Foundation.Clarify.ClarifyDataSet($ClarifySession);
	$usersGeneric = $dataSet.CreateGeneric("tagged_case_alst");
	$usersGeneric.AppendFilter("tag", "Equals", $watchTag);
	$usersGeneric.DataFields.Add("tag_owner_name")  > $null;
	$usersGeneric.IsDistinct = $True;	
	$usersGeneric.Query();
	$usersGeneric.Rows;

	write-debug ('number of watchers:' + $usersGeneric.Rows.Count);
}

function GetWatchedCases(){
	foreach( $row in $input){
		log-debug("getting watched cases for " + $row["tag_owner_name"]);
		
		$dataSet = new-object FChoice.Foundation.Clarify.ClarifyDataSet($ClarifySession)
		$watchedCasesGeneric = $dataSet.CreateGeneric("tagged_case_alst")
		$watchedCasesGeneric.AppendFilter("tag", "Equals", $watchTag);
		$watchedCasesGeneric.AppendFilter("entry_time", "After", $timeAgo);
		$watchedCasesGeneric.AppendFilter("tag_owner_name", "Equals", $row["tag_owner_name"]);
		$watchedCasesGeneric.DataFields.Add("parent_id")  > $null;
		$watchedCasesGeneric.IsDistinct = $True;
		$watchedCasesGeneric.Query();

log-debug("found activity on watched cases: " + $watchedCasesGeneric.Count);

		$caseIdArray = @();

		foreach( $case in $watchedCasesGeneric.Rows){
			$caseIdArray+=$case["parent_id"];  
		} 
		$caseIds = $caseIdArray -join ',';

		$cases = New-Object System.Object;							
		add-member -in $cases noteproperty watcher $row["tag_owner_name"];
		add-member -in $cases noteproperty caseIds $caseIds;
			
		$cases;
	} 
} 


function GetWatchedCasesWithNoActivity(){
	foreach( $messageBody in $input){
		$watcher = $messageBody.watcher;
		log-debug("getting watched cases with no activity for " + $watcher);

		$dataSet = new-object FChoice.Foundation.Clarify.ClarifyDataSet($ClarifySession)
		$watchedCasesWithNoActivityGeneric = $dataSet.CreateGeneric("tagged_case_alst")
		$watchedCasesWithNoActivityGeneric.AppendFilter("tag", "Equals", $watchTag);		
		$watchedCasesWithNoActivityGeneric.AppendFilter("modify_stmp", "Before", $timeAgo);
		$watchedCasesWithNoActivityGeneric.AppendFilter("tag_owner_name", "Equals", $messageBody.watcher);
		$watchedCasesWithNoActivityGeneric.DataFields.Add("parent_id")  > $null;
		$watchedCasesWithNoActivityGeneric.IsDistinct = $True;
		$watchedCasesWithNoActivityGeneric.Query();

		log-debug("found watched cases with no activity: " + $watchedCasesWithNoActivityGeneric.Count);

		$messageBody+="<hr/>";
		$messageBody+= header1("Watched cases with no recent activity")
		if ($watchedCasesWithNoActivityGeneric.Count -eq 0){
			$messageBody+= paragraph("None found")	
		}

		$caseIdArray = @();
		foreach( $case in $watchedCasesWithNoActivityGeneric.Rows){
			#$caseIdArray+=$case["parent_id"];  

				$caseRow = get-caseview-by-id $case["parent_id"]
				$c = get-case-by-id $case["parent_id"]

				$caseIdLink = "<a href=" + $agent5Url + "/support/cases/" + $case["parent_id"] + ">Case " + $case[
				"parent_id"] + "</a>"
				$messageBody+=header2($caseIdLink);	
				
				$messageBody+=div "" "summary"
				$messageBody+= paragraph($caseRow["title"]);																										
				$messageBody+=paragraph("For " + $caseRow["first_name"] + " " +  $caseRow["last_name"] + " at " + $caseRow["site_name"])				
				$messageBody+= paragraph("Owned by " +  $caseRow["owner"]);
				$messageBody+= paragraph("Last Modified " +  $c["modify_stmp"]);
				
				if ($caseRow["condition"] -eq "Closed"){
					$messageBody+= paragraph("Case is Closed")	
				}else{
					$messageBody+= paragraph("Case is Open with a status of " + $caseRow["status"])					
				}
				$messageBody+=endDiv;	
		}

		$messageBody+=footer("Brought to you by Dovetail Software")
		$messageBody = $messageBody | add-member noteproperty watcher $watcher -passThru;	
		$messageBody;
	} 
} 


function GetCaseHistories(){
	$acceptHeader = "application/json";
	#$acceptHeader = "text/html";

	foreach( $i in $input){		
		$webClient = new-object "System.Net.WebClient"
		$webClient.Headers.Add("Accept", $acceptHeader);

		log-debug("getting case histories for " + $i.watcher + " since " + $timeAgo);
				
		$URL=$BASEURL+'?Ids=' + $i.caseIds + '&Since=' + $timeAgo + '&authToken=' + $authToken;

		log-debug("getting URL: " + $URL);
				    
		try {
				$response = $webclient.DownloadString($URL);
				$response = $response | add-member noteproperty watcher $i.watcher -passThru;				
				$response;
		}
		catch [Net.WebException] {
				$e = $_.Exception
				$response = $e.Response;
				$requestStream = $response.GetResponseStream()
				$readStream = new-object System.IO.StreamReader $requestStream
				new-variable db
				$db = $readStream.ReadToEnd()
				$readStream.Close()
				$response.Close()
				$db;		
				$httpStatusCode = [int]$response.StatusCode
				log-error("HTTP Status:" + $httpStatusCode);
				log-error($db);
				#exit;
		}		
	}
}

function SendEmail(){	
	foreach( $message in $input){
		$row = get-empl-view-by-login-name $message.watcher;
		$to = $row["e_mail"];

		$message+= "<br/>Report intended for " + $row["e_mail"];		
		log-debug("sending email to " + $to);

		$smtpmail = [System.Net.Mail.SMTPClient]("$smtpServer")
		$smtpmail.Port =$port;
		$smtpmail.EnableSsl = $true;
		$smtpmail.UseDefaultCredentials = $false
		$smtpmail.Credentials = New-Object System.Net.NetworkCredential($smtpLogin, $smtpPassword);
		$mailMessage = new-object System.Net.Mail.MailMessage($from, $to);
		$mailMessage.Subject = $subject;
		$mailMessage.IsBodyHTML = $true;
		$mailMessage.Body = $message;
		$smtpmail.Send($mailMessage);
		}	
}


function InlineCss(){
	$url="https://us8.api.mailchimp.com/2.0/helper/inline-css.json";
	$strip_css="true";

	foreach( $html in $input){
		$postParams = @{"strip_css"="true";"apikey"="$mailChimpApiKey"};
		$postParams["html"] = $html;
		$result=Invoke-WebRequest -Uri $url -Method POST -Body  $postParams  | ConvertFrom-Json

		$messageBody = $result.html;
		$messageBody = $messageBody | add-member noteproperty watcher $html.watcher -passThru;	
		$messageBody
	}
}


function ParseJSONIntoHTML(){
	add-type -assembly system.web.extensions
	$jsSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer

	foreach( $json in $input){
		log-debug("Parsing JSON Into HTML");
		
		$jsonResult = $jsSerializer.DeserializeObject( $json ) 
		$messageBody = "";
		$messageBody+=$css;
	
		$messageBody+= header1("Recent activity on your watched cases")
		#$messageBody+=paragraph("The following activity occured on your watched cases since " + $jsonResult["Since"] );

		$items = $jsonResult["HistoryItems"];
		$previousId = "";

		if ($items.Count -eq 0){
			$messageBody+= paragraph("None found")	
		}

		foreach ($item in $items){
			if ($previousId -ne $item["Id"]){
				$previousId = $item["Id"];

				$caseRow = get-caseview-by-id $item["Id"]

				$caseIdLink = "<a href=https://support.dovetailsoftware.com/agent5/support/cases/" + $item["Id"] + ">" + (Get-Culture).TextInfo.ToTitleCase($item["Type"]) + " " + $item["Id"] + "</a>"
				$messageBody+=header2($caseIdLink);	
				
				$messageBody+=div "" "summary"
				$messageBody+= paragraph($caseRow["title"]);																										
				$messageBody+=paragraph("For " + $caseRow["first_name"] + " " +  $caseRow["last_name"] + " at " + $caseRow["site_name"])				
				$messageBody+= paragraph("Owned by " +  $caseRow["owner"]);
				
				if ($caseRow["condition"] -eq "Closed"){
					$messageBody+= paragraph("Case is Closed")	
				}else{
					$messageBody+= paragraph("Case is Open with a status of " + $caseRow["status"])					
				}
				$messageBody+=endDiv;											
			}				

			$messageBody+=div "" "history"
						
				$messageBody+=div "" "history-header"													
					$by = " by " + $item["Who"]["Name"];					
					$at = " at " + $item["When"]
					$messageBody+=$item["Title"] + "<span class=who-when>" + $by + $at + "</span>";					
				$messageBody+=endDiv;

				$messageBody+=div "" "history-body"
			
					if ($item["Detail"].length -gt 0){ 
						$messageBody+=$item["Detail"]
					}			
					if ($item["Internal"].length -gt 0){ 
						$messageBody+=div "Internal Notes:" "internal-header"
						$messageBody+=endDiv;
						$messageBody+=div $item["Internal"] "internal"
						$messageBody+=endDiv;
					}
				$messageBody+=endDiv;
			$messageBody+=endDiv;
		}
		
		$messageBody = $messageBody | add-member noteproperty watcher $json.watcher -passThru;								
		$messageBody;
	}
}

$results = GetWatchers | GetWatchedCases  | GetCaseHistories | ParseJSONIntoHTML |  GetWatchedCasesWithNoActivity | InlineCss | SendEmail;
$results;
