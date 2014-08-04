case-watcher
============

Creates a watched cases report and sends it via email.

Watched cases are those tagged "watch"

## Dependencies
1. [Dovetail Bootstrap](https://github.com/DovetailSoftware/dovetail-bootstrap) - used for generating recent case history information
1. [MailChimp](http://mailchimp.com/) - used for in-lining CSS. Sign up for a free account.
1. [Dovetail Agent 5](https://support.dovetailsoftware.com/selfservice/products/show/Dovetail%20Agent)

## Install
1. Apply schemascript using Dovetail SchemaEditor
1. Configure database settings in dovetail.config
1. Configure logging settings in logging.config
1. Configure settings in WatchedCasesReport.ps1
  * $smtpServer
  * $port
  * $smtpLogin
  * $smtpPassword
  * $from
  * $BASEURL - URL to Dovetail Bootstrap case histories api
  * $authToken  - Dovetail Bootstrap auth token
  * $agent5Url - URL to Dovetail Agent 5 web application
  * $mailChimpApiKey - Mail Chimp api token
1. Setup Windows scheduled task
  * Create a scheduled task to execute the **RunReport.bat** file
  * Suggested: Run report daily at 6:00 AM
