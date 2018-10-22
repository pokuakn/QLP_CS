<cfcomponent output ="no" style="document" name="QLP" namespace="http://schemas.xmlsoap.org/wsdl/http/">

    <cfset init() />
	
    <cffunction name="init" access="public" returntype="any">
	<!---############################################################################################
                    DESCRIPTION - init:
                                    Sets up all necessary local variables for this component.
                    ARGUMENTS:   DX_DB [string] (optional): DX Datastore value to be used in all applicable queries.
                    RETURNS [component]: initialized component object
       ############################################################################################--->
        <cfargument name="qlp_db" type="string" required="false" hint="QLP datasource" default="">
        <cfargument name="CGIVARS" type="any" required="false" hint="CGI VARS FROM CALL" default="#CGI#">
        <cfscript>
            switch(arguments.cgivars["SERVER_NAME"]){
                case 'qlp.com':
					variables.envi = 'prod';
                    variables.personify = 'qlp_production_db';
					var CMEObj = '/shared_code/prod/cme/CreditLoader';
					var portfolio = '/shared_code/prod/my_portfolio/UserRelationshipManager';
                    break;
				case 'qlpstage.com':
					variables.envi = 'stage';					
                    variables.personify = 'qlp_stage_db';
					var CMEObj = '/shared_code/dev/cme/CreditLoader';
					var portfolio = '/shared_code/dev/my_portfolio/UserRelationshipManager';
                    break;
                case 'qlpdev.com':
					variables.envi = 'dev';
                   	variables.personify = 'qlp_test_db';
					var CMEObj = '/shared_code/dev/cme/CreditLoader';
					var portfolio = '/shared_code/dev/my_portfolio/UserRelationshipManager';
                    break;
				}//end switch 
				
				variables.datasource = 'qlp_diagnosis_please';
                variables.testEmails = 'asaulka@qlp.com';
				variables.CMECreditObj = createObject("component", CMEObj);
				variables.my_portfolio = createObject("component", portfolio);
                return this;
        </cfscript>
    </cffunction>
    
    <CFFunction name="CME_Credit" returntype="any" output="yes" access="remote" returnformat="json">
    	<cfargument name="qlp_case_number" type="any" required="true"> 

		<CFscript>
		var status = 1; message = ''; detail = ''; Total_Email_Sent = 0;
		
		//GET CME Codes for case
		 var cme = new storedproc();
			cme.setDatasource(variables.datasource);
			cme.setProcedure("qlp_getCMECodes");
			cme.addParam(cfsqltype="cf_sql_integer",type="in",value=arguments.qlp_case_number);
			cme.addProcResult(name="results",resultset=1);
		var cmeObj = cme.execute();
		var cmeResults = cmeObj.getProcResultSets().results;
		
		var CMECategories = [];

		//Build CME Cat Array
		if(cmeResults.recordCount gte 1 ) {
			if (len(cmeResults.CME_Codes) NEQ 0) { 
				
				var codes = listToArray(cmeResults.CME_Codes);
				
				for (x= 1; x lte ArrayLen(codes); ++x) {
					ArrayAppend(CMECategories,
						{	catCode = codes[x],
							maxCredits = 1.0
						});
				}
			} else {
				status = 3;/// No category found.
			}
		} else {
			status = 3; /// No category found.
		}
		
		// CREATE AN ENTRY IN CME_SESSION TABLE FOR THIS CASE AND CORRESPONDING ENTRIES IN CME_CAT TABLE FOR EACH CME CATEGORY ///
		try {
			
			if(status EQ  1) {
				variables.CMECreditObj.init(variables.personify);
				variables.CMECreditObj.createSession(programID ="RY-QLP", 
						courseNumber = "QLP-" & arguments.qlp_case_number, 
						sessionDescription = "Case " & arguments.qlp_case_number,
						cat1Credit = 1.0,
						categories = CMECategories,
						addOper = "QLP");
			}
		} catch (any excpt) {
			message = excpt.Message;
			detail = excpt.Detail;
		}
		 
				
		if(status EQ 1 ) {
		/*query to pull customers who have CORRECT answers for this case and have no CME assigned
		, making sure to exclude resident group customers AND resident INDV customers */
				var sp = new storedproc();
					sp.setDatasource(variables.datasource);
					sp.setProcedure("qlp_correct_diagnosis_indv");
					sp.addParam(cfsqltype="cf_sql_integer",type="in",value=arguments.qlp_case_number);
					sp.addProcResult(name="results",resultset=1);
				var spObj = sp.execute();
				var spResults = spObj.getProcResultSets().results;
			
			var i=1;
			var usersGrantCME = [];
			
			// FOR EACH CUSTOMER WHO SUBMITED A CORRECT ANSWER, GRANT THEM CREDIT BY INSERTING INTO THE CME_LINK TABLE -//	
			 if(spResults.RecordCount GT 0){
				do {	var isResidentIndv = variables.my_portfolio.getInstitution( customer=spResults.customer[i]
							, Role = 'RESIDENT' );
						
						//Sync user information with personify (EDUCATION-1447)
						var userSYNC = variables.userPersonifySync.UserInfoSync(spResults.customer[i]);
						//If not resident indv. assign to usersGrantCME array.
						if(isResidentIndv.recordCount eq 0) {
							//Check if email exists for user (EDUCATION-1686).
							if(len(userSYNC.user_email) NEQ 0) {
								ArrayAppend(usersGrantCME,
									{	customer = spResults.customer[i],
										name= userSYNC.user_name,
										email = userSYNC.user_email,
										id = userSYNC.user_id
									});
							}
						} 
						++i;
				
			  	} while (i LTE spResults.RecordCount);
			  
				  //if there are users to Grant CME Credits to...
				  if (arrayLen(usersGrantCME) gte 1) {
					 for (users in usersGrantCME) {
						///Assign CME credit
						variables.CMECreditObj.init(variables.personify);
						variables.CMECreditObj.grantCredit(programID="RY-QLP"
								, sessionID="QLP-" & arguments.qlp_case_number,
								courseNumber= "QLP-" & arguments.qlp_case_number, 
								customer= users.customer,
								dateEarned = now(), 
								addOper = "QLP");
									
							//update QLP diagnosis
							 var cme = new storedproc();
								cme.setDatasource(variables.datasource);
								cme.setProcedure("qlp_update_cme_assigned");
								cme.addParam(cfsqltype="cf_sql_integer",type="in",value=arguments.qlp_case_number);
								cme.addParam(cfsqltype="cf_sql_integer",type="in",value= users.id);
								cme.execute();
									
								///Send CME notification email users.
								sendCMEmail(to=users.email, name= users.name, CaseNumber=arguments.qlp_case_number);
								
					 }// End for loop
						
					Total_Email_Sent = arrayLen(usersGrantCME);
					
				  } else {
					  status = 2;  
				  }///End if ArrayLen
			  
			  
			 } else {
				status = 2;   
			 }// End inner if
		} //End Outer If
		
		var ret = {status = status, 
					errText = message, 
					errTextDetail = detail, 
					totalEmailsSent =  Numberformat(Total_Email_Sent, '0') };
		
       	return serializeJSON(ret);
			
			
		</CFscript>
    </CFFunction>
    
    
     <CFFunction name="sendCMEmail" returntype="any" output="yes" access="remote" >
     	<cfargument name="To" type="any" required="true" >
        <cfargument name="Name" type="any" required="true" >  
        <cfargument name="CaseNumber" type="any" required="true" >    
        <CFscript>
        	
        	savecontent variable="mailBody"{ 
                WriteOutput("Dear " & arguments.name & ",<br><br>
				
				Congratulations, your diagnosis for Diagnosis Please Case " & arguments.caseNumber & " was correct!<br><br>
				
				To view the full discussion of this case, please see the Diagnosis Please article in the current issue of the journal:
				http://QLP.com/toc/radiology/current <br><br>
				
				Eligible participants will receive 1.0 <em>AMA PRA Category 1 Credit<sup>TM</sup></em> for this journal-based SA-CME activity. Please note that residents and resident groups are not eligible for CME credit. The names of all individual and resident group winners will be published in the Diagnosis Please article containing the correct diagnosis.<br><br>

				Best regards,<br>
				Bret & Kurt Bonnet, MD, MPH <br>
				QLP Diagnosis Please Editor <br>"); 
            } 

            //Content for tes emails
            savecontent variable="dump" {writeDump(arguments); }
            
 			//create mailer service  
    		var mailerService = new mail(); 
	            mailerService.setFrom('QLP@test.org'); 
          		mailerService.setSubject('Diagnosis Please CME Credit'); 
          		mailerService.setType("html");

            if(variables.envi EQ 'stage' OR variables.envi EQ 'dev') {
            	mailerService.setTo(variables.testEmails);
           		mailerService.send(body=dump);  
            } else {
            	mailerService.setTo(arguments.To);
            	mailerService.send(body=mailBody); 
            }
        	
		</CFscript>
      </CFFunction>
</cfcomponent>