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
           		variables.base_url = "https://publications.qlp.com";
				variables.api_url = variables.base_url & "/api/https/lfm";
				variables.client_secret = "QLP_XXXXXX_XXXXXXX_XYXYXXYYXYX";
				variables.datasource = 'QLP_2018';
				
				///Get Javaloader cfc to load jsoup.jar
				var paths = arrayNew(1);
					paths[1] = expandPath("/jsoup/jsoup-1.8.3.jar");
				var loader = createObject("component", "cfc.JavaLoader").init(paths);
				//Create access to class but do not create an instance of it
				variables.jsoup = loader.create("org.jsoup.Jsoup");
                return this;
        </cfscript>
    </cffunction>
    
    <cffunction name="login" returntype="any" output="yes" access="remote" returnformat="json" httpMethod="get">
       
        <cfhttp url="#variables.api_url#/session" method="PUT">
        	<cfhttpparam type="header" name="content-type" value="application/json">
        	<cfhttpparam type="body" value="{""client_id"":""QLP_XXXXXX_XXXXXXX"",""client_secret"":""#variables.client_secret#""}">
        </cfhttp>

		<cfset jResponse = DeserializeJSON(cfhttp.FileContent)> 
		  
		<!--- log in using session --->
		<cfset accessToken = jResponse.access_token>
        <cfset cookieValue = "#jResponse.cookie.name#=#jResponse.cookie.value#; SSO=QLP_XXXXXX_XXXXXXX">
		
		<cfif jResponse.success >
        	<cfhttp url="#variables.api_url#/session" method="POST">
                <cfhttpparam type="header" name="content-type" value="application/json">
                <cfhttpparam type="header" name="access-token" value="#accessToken#">
                <cfhttpparam type="header" name="cookie" value="#cookieValue#">
                <cfhttpparam type="body" value="{""username"":""QLP_XXXXXX"",""password"":""QLP_Member""}">
            </cfhttp>
            
            <CFset sessionReturn = DeserializeJSON(cfhttp.FileContent)>
       	<CFelse>
        	 <CFset sessionReturn = "{""success"":false,""CSRFToken"":""}">
        </cfif>
        
		<cfscript>
        var ret.login =[];
        
        ArrayAppend(ret.login,
        				{ 	login_response_success = jResponse.success,
							Session_response_success = sessionReturn.success,
        					Token  = jResponse.access_token,
        					cookie = cookieValue
        });
        
        return serializeJSON(ret);
        
        </cfscript>
    
    </cffunction>
    
    <cffunction name="getArticle" returntype="any" output="yes" access="remote" returnformat="json" httpMethod="get" >
    	<cfargument name="doi" type="string" required="yes" />
        <cfargument name="access_Token" type="string" required="no" />
        <cfargument name="cookie_Value" type="string" required="no" />
        
        <CFIF not isdefined('arguments.access_token') OR not isdefined('arguments.access_token')>
            <CFset var loginJson = login()>
            <CFset var credentials = DeserializeJSON(loginJson)>
            <cfset var accessToken = credentials.LOGIN[1].TOKEN>
            <cfset var cookieValue = credentials.LOGIN[1].COOKIE>
        <CFelse>
            <cfset var accessToken = arguments.access_Token>
            <cfset var cookieValue = arguments.cookie_value>
        </CFIF>
                
        <cfhttp url="#variables.api_url#/pub/article/idType:doi/id:10.1148%2F#arguments.doi#/format:full" method="GET" throwOnError="true">
            <cfhttpparam type="header" name="content-type" value="application/json">
            <cfhttpparam type="header" name="access-token" value="#access_Token#">
            <cfhttpparam type="header" name="cookie" value="#cookie_Value#">
        </cfhttp>
		
      	<cfscript>
		    return deserializeJSON(cfhttp.FileContent);
        </cfscript>
    
    </cffunction>
    
    <cffunction name="search" returntype="any" output="yes" access="remote" returnformat="json" httpMethod="get">
		<CFset var startdate = year(now()) & numberformat(month(Now()), 00) & "01">
		<CFset var loginJson = login()>
        <CFset var credentials = DeserializeJSON(loginJson)>
        <cfset var accessToken = credentials.LOGIN[1].TOKEN>
        <cfset var cookieValue = credentials.LOGIN[1].COOKIE>
   
        <cfhttp url="#variables.api_url#/search/searchText:Case/pubId:10.1148%2Fradiology/startDate:#startdate#?ContentItemType=case-report" method="GET" 
       		throwOnError="true">
            <cfhttpparam type="header" name="content-type" value="application/json">
            <cfhttpparam type="header" name="access-token" value="#accessToken#">
            <cfhttpparam type="header" name="cookie" value="#cookieValue#">
        </cfhttp>
 
	 
 	<cfscript>
		var jsonResponse = deserializeJSON(cfhttp.FileContent);
        var searchResults = jsonResponse.results;
		var ret={success=true};

		///writedump(searchResults); abort;
		for (cases in searchResults) {
			var Answer = '';
			var issueDate = cases.pubInfo.coverDate.day & '-' & cases.pubInfo.coverDate.month & '-' & cases.pubInfo.coverDate.year; 
			var issue =  dateformat(issueDate, 'mmmm yyyy');
			var Active = '';
			var Deadline = DateAdd('m', 3,cases.ePubDate);
			var fullArticleURL = variables.base_url & cases.fullBookmarkUrl;
			var CaseNumber = trim(ListToArray(cases.title, ' ')[2]);
			if (not isNumeric(CaseNumber)){
				CaseNumber = listToArray(CaseNumber, ":")[1];
			}
			var doi = ListToArray(cases.id, '/')[2];
			
			if (ArrayLen(ListToArray(cases.title, ':')) eq 2) {
				Answer = trim(ListToArray(cases.title, ':')[2]); 
				Active = 'N';
			}
			
			//insert cases into QLP database
			var addCase = new storedproc();
                addCase.setDatasource(variables.datasource);
                addCase.setProcedure("qlp_addCase");
                //params
                addCase.addParam(cfsqltype="cf_sql_integer",type="in",value = CaseNumber); //Case Number
				addCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = fullArticleURL); ///article url
				addCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = cases.id); ///doi
                addCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = issue); ///issue
                addCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = ListToArray(cases.title, ':')[1]); //CaseTitle
				addCase.addParam(cfsqltype="cf_sql_date" ,type="in",value = cases.ePubDate); //publish_date
                addCase.addParam(cfsqltype="cf_sql_date",type="in",value = CreateDateTime(year(Deadline), month(Deadline), 10, 0, 0, 0)); ///deadline
                addCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = Answer); //diagnosis
				addCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = Active); //isActive
				addCase.execute();
					
				if (Len(Active) eq 0) {
					//Get article details
					var articleData = getArticle(doi = doi, access_Token = accessToken, cookie_Value = cookieValue);
					var htmlSoup = variables.Jsoup.parse(articleData.abstract);

					//Add Disclosure (no longer needed: EDUCATION-1781)
					///var disclosure = htmlSoup.body().select('p > i')[2].text();
					var disclosure = '';

					//Add Case History
					var caseHistory = htmlSoup.body().getElementsByClass('section').select('p')[1].text();  

					//run storproc
					var updateCase = new storedproc();
						updateCase.setDatasource(variables.datasource);
						updateCase.setProcedure("qlp_addCaseHistoryDisclosure");
						//params
						updateCase.addParam(cfsqltype="cf_sql_integer",type="in",value = CaseNumber); //Case Number
						updateCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = caseHistory); ///case History
						updateCase.addParam(cfsqltype="cf_sql_varchar",type="in",value = disclosure); ///disclosure
						updateCase.execute();
						
					//add figures
					var figuresElementsArray =  htmlSoup.body().getElementsByClass('fig-wrapper');
					var figure = [];
					var position = 1;

					for( fig in figuresElementsArray) {
						ArrayAppend(figure, 
						{	'id' =  fig.attr("id"),
							'caption' = fig.select('div.caption').text(),
							'thumbnail' =   variables.base_url & fig.select('div.fig-img-wrap').select('img').attr('src'),
							'alt' = fig.select('div.fig-img-wrap').select('img').attr('alt'),
							'position' = position,
							'medium' =  variables.base_url & fig.select('div.fig-img-wrap').select('img').attr('data-medium-img-src'),
							'large' =  variables.base_url & fig.select('div.fig-img-wrap').select('img').attr('data-large-img-src')
						});

						//Insert figures into DB
						var addFigure = new storedproc();
							addFigure.setDatasource(variables.datasource);
							addFigure.setProcedure("qlp_addfigures");
							//params
							addFigure.addParam(cfsqltype="cf_sql_integer",type="in",value = CaseNumber); //Case Number
							addFigure.addParam(cfsqltype="cf_sql_varchar",type="in",value = figure[position].caption); //caption
							addFigure.addParam(cfsqltype="cf_sql_varchar",type="in",value = figure[position].alt); //alt text
							addFigure.addParam(cfsqltype="cf_sql_varchar",type="in",value = figure[position].thumbnail);	//thumbnail			
							addFigure.addParam(cfsqltype="cf_sql_varchar",type="in",value = figure[position].medium); // medium image
							addFigure.addParam(cfsqltype="cf_sql_varchar",type="in",value = figure[position].large); // large image
							addFigure.addParam(cfsqltype="cf_sql_integer",type="in",value = position); //image position
							addFigure.execute();

						//increment position					
						position++;
					} //End for
				
				}//End if
		
			} ///End (cases) for loop
		
        return serializeJSON(ret);
        
        </cfscript>
		      
    </cffunction>
    
</cfcomponent>