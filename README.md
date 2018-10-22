# QLP_CS
ColdFusion Code Samples

Coldfusion Code Sample:
Use case: 
To maintain their medical licenses, doctors are required to accumulate a certain number of Continuing Medical Education (CME) points from an accredited institution. 
So, for this 'Diagnosis Please' application, we post difficult cases each month for doctors to solve. Once posted, the case remains open for 3 months, then it is deactivated.  Doctors/Fellows who provide correct answers during the 3-month window get awarded up to a total of 8.75 CME points, and 0.00 CME Points for Residents or Resident groups. 
We get the cases every month from a medical journal API (PUBInfo) via CFHttp request which is set up as a scheduled task to run monthly.

Sample Code Breakdown: 
CallPUBInfoAPI.cfc  (Dependencies: jsoup-1.8.3.jar)
CFHttp is used to get the cases from PUBInfo web services, parse through the HTML response, using a 3rd party utility called Jsoup, harvest info I need, such as (Case Title, Case Number, Description, Publication dates, Issue, Article URL, Diagnosis / Answer, Images/figures)  and insert into the diagnosis please database.

Methods:
#init: sets up all necessary local variables for this component.
login: sends login credentials to PUBInfo server.
getArticle: gets a specific article from PUBInfo server with given article id. 
search: searches for articles within a given set of constraints from PUBInfo API. This method demonstrates how to connect to a 3rd party API, and handle the response. Breakdown: I loop through the search results to get basic publication information, then I use getArticle() to get specific article information. Finally, still within the loop, I apply JSoup Parser to the results from getArticle() and harvest the information I need into the database using pre-built store procedures.

GrantCME.cfc 
This CFC grants CME credits to doctors who submitted correct answers to the cases published. 

Methods: 
init: This is to demonstrate how other cfcs can be called into this cfc simulating inheritance similar to a OOP coding style.
cme_credit: This is to demonstrate using loops with CFscript and how I can account for different business rules. 
sendCMEEmail: This is to demonstrate sending emails using CFscript. 
All other CFCs are related to and written by JSOUP!!!!!
