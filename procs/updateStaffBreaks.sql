if object_id('updateStaffBreaks') is not null
	drop procedure updateStaffBreaks
go

create procedure updatestaffbreaks(@StaffID int, @dDay smalldatetime = null, @uid int = 0) as
begin

with cte as (
	select sa.[id]
	, sa.staffID
	, seh.breakEntitlement
	, dDate
	, timeFrom
	, timeTo
	, sum(datediff(minute,timeFrom,timeTo)) over (partition by sa.staffID, dDate) as DayShiftTotal
	, row_number() over (partition by sa.staffID, dDate order by datediff(minute,timeFrom,timeTo) desc, sa.[id]) as ind
	from staffassign sa
	inner join StaffEmploymentHistory seh on sa.staffID= seh.staffID
										  and (dateadd(day,datediff(day,0,getdate()),0) between dFrom and dTo
										  and seh.isExternal = 0)
	where sa.staffID = @StaffID
)
update sa
	set breakentitlement = case when DayShiftTotal > 360 then coalesce(cte.breakEntitlement,0) else 0 end
	from StaffAssign sa
	inner join cte on sa.[id] = cte.[id]
where
	cte.ind = 1
	and (
			(
				@dDay is null
				and sa.dDate >= cast(current_timestamp as date)
			)
		or
			(
				sa.dDate = @dDay
			)
		)
end

go