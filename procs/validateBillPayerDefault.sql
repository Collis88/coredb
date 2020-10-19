drop procedure validateBillPayerDefault 
go

create procedure validateBillPayerDefault 
    ( @billPayerID bigint
	, @surname varchar(50) output
	, @forename varchar(50) output
	, @title smallint output
	, @address1 varchar(50) output
	, @address2 varchar(50) output
	, @address3 varchar(50) output
	, @address4 varchar(50) output
	, @address5 varchar(50) output
	, @postcode varchar(20) output
	, @telhome varchar(30) output
	, @telwork varchar(30) output
	, @telmob varchar(30) output
	, @usualPaymentMethod int output
	, @BPStatus int output
	, @email varchar(100) output
	, @salutation varchar(100) output
	, @accname varchar(150) output
	, @sortcode varchar(20) output
	, @accnumber varchar(50) output
	, @reference varchar(50) output
	, @usualpayfreq int output
	, @bp_ref varchar(50) output
	, @siteID int output
	, @openingBalance smallmoney = 0 output
	, @AllowedPaymentMethods varchar(max) = '' output
	--, @contactsIDRet int = null output
	, @notes varchar(5000) = '' output
	, @billingSalutation varchar(100) = null output
	, @DDAdj smallmoney = null output
	, @DDDueDate varchar(20) = '' output
	, @CustomCoreRef varchar(50) = '' output
	, @DisableRetroBilling bit = 0 output
	, @CustomCoreRef2 varchar(50) = '' output
	, @CompanyInd bit = 0 output
	, @Initials varchar(10) = '' output
	, @Prefix varchar(20) = '' output
	, @KnownAs varchar(30) = '' output
	, @Gender char(1) = 'U' output
    ) as

    declare @accNumberProc varchar(max), @customCoreRefProc varchar(max) = '', @customCoreRef2Proc varchar(max) = ''
    select @accNumberProc = value from Lookup where item = 'AccountNumberValidation'
    select @customCoreRefProc = right(value, len(value) - charindex('#', value, 1)) from Lookup where item = 'BPCustomCoreRef' and value like '%#%'
	select @customCoreRef2Proc = right(value, len(value) - charindex('#', value, 1)) from Lookup where item = 'BPCustomCoreRef2' and value like '%#%'
--    select @accNumberProc, @customCoreRefProc -- NEDB - is this just for debug (can't see this "return" value is used by front end?)?
    
    declare @msg table (msg varchar(max))

    -- Custom account number validations
    if @accNumberProc like 'validate%' begin
        insert @msg exec @accNumberProc @accnumber
        select 'error', msg from @msg where len(msg) > 0
    end 
    
    -- Custom core ref validation
    if len(@customCoreRefProc) > 0 begin
        delete @msg 
		If exists(select * from sys.all_objects o join sys.all_parameters p on p.object_id = o.object_id and o.name = @customCoreRefProc and p.name = '@bpid')
			insert @msg exec @customCoreRefProc @CustomCoreRef, @billpayerID
		else
			insert @msg exec @customCoreRefProc @CustomCoreRef

        select 'error', msg from @msg where len(msg) > 0
    end
    
	-- Custom core ref 2 validation
    if len(@customCoreRef2Proc) > 0 begin
        delete @msg 

        insert @msg exec @customCoreRef2Proc @CustomCoreRef2
        select 'error', msg from @msg where len(msg) > 0
    end

    set @accnumber = ltrim(rtrim(@accnumber))
    set @accname = ltrim(rtrim(@accname))
    set @sortcode = ltrim(rtrim(@sortcode))
    set @reference = ltrim(rtrim(@reference))

    if @accname <> '' or @accnumber <> '' or @sortcode <> '' or @reference <> '' begin
		IF not exists(select 1 from Lookup where item = 'DD-FCC-USE-PAPERLESS' and value = '1') begin
			-- FCC Paperless allows direct debit but with no account details entered, as these are populated via the API
			if @accname = '' select 'error', 'You have entered details in the direct debit section, but have entered no account name'
			if @accnumber = '' select 'error', 'You have entered details in the direct debit section, but have entered no account number'
			if @sortcode = '' select 'error', 'You have entered details in the direct debit section, but have entered no sortcode'
			if @reference = '' select 'error', 'You have entered details in the direct debit section, but have entered no reference'
		end

        if exists (select 1 from SiteLookup where item = 'BILL-DDLoginID' and value <> '') begin
			-- FCC Validation
            IF not exists(select 1 from Lookup where item = 'DD-FCC-USE-PAPERLESS' and value = '1') begin
				if len(@sortcode) < 6 select 'error', 'The direct debit sort code must be 6 characters long (e.g. 012345)'
				if len(@accnumber) < 8 select 'error', 'The direct debit account number must be 8 characters long (i.e. 00123456)'
			end 

            declare @code int
            exec @code = validateBPReference @bpID = @billPayerID, @bpRef = @reference 
            if @code = 1 select 'error', 'Billpayer reference must be between 6 and 18 characters long if DD Collection is enabled.'
            if @code = 2 select 'error', 'Billpayer reference must be unique.', 16, 1

            -- Other validation for FCC web service
            if ltrim(rtrim(@forename)) = '' select 'yesno', 'If you wish to register this billpayer for DD Collection, you must enter a Forename. Continue without a Forename?'
            if ltrim(rtrim(@surname)) = '' select 'yesno', 'If you wish to register this billpayer for DD Collection, you must enter a Surname. Continue without a Forename?'
            if ltrim(rtrim(@postcode)) = '' select 'yesno', 'If you wish to register this billpayer for DD Collection, you must enter a Postcode. Continue without a Postcode?'
            if ltrim(rtrim(@address1)) = '' select 'yesno', 'If you wish to register this billpayer for DD Collection, the first address line cannot be blank. Continue without a first address line?'
            if ltrim(rtrim(@address2)) = '' select 'yesno', 'If you wish to register this billpayer for DD Collection, the second address line cannot be blank. Continue without a second address line?'
            if ltrim(rtrim(@email)) = '' select 'yesno', 'If you wish to register this billpayer for DD Collection, you must enter an Email address. Continue without an Email address?'

            if (select description from ContactTitle where titleID = @title) not in ('Mr', 'Mrs', 'Miss', 'Ms', 'Dr')
                select 'yesno', 'If you wish to register this billpayer for DD Collection, the billpayer''s title must be one of Mr, Mrs, Miss, Ms or Dr. Continue with the current title?'
        end
        
        -- The 'referenceTextOK' field doesn't seem to do anything (all it validates is that *something* has been entered, but that's already validated above).
        --else begin 
        --    ... "The direct debit reference must be 6 characters long excluding non-alphanumeric characters, and not contain all the same character"
        --end
    end

	 -- email
    if len(@email) > 0 and (@email not like '_%@_%._%')
	begin
		select 'error', 'Please enter a valid email address!'
	end
 go

