-- If C1 report template modified, undo "upgrade" to previous version
-- Also tidy up previous "upgrades" to same version.
exec executesql N'
select type , item , data , Notes
,MIN(id) as minID, MAX(cast(active as int)) as active
into #t
from typeData
group by type , item , data , Notes
having COUNT(*) > 1

delete typeData
from typeData td
join #t t on t.Notes = td.Notes and t.data = td.data
  and t.item = td.item and t.type = td.type 
  and td.id <> t.minID
  
update typeData set active = t.active
from typeData td
join #t t on t.Notes = td.Notes and t.data = td.data
  and t.item = td.item and t.type = td.type 
  and td.id = t.minID
  
drop table #t

--select id, type , item , data, active
--,case when cast(getdate() as float) - CAST(modified as float) < 0.5 and active = 1 then 1 else 0 end as modind
--,ROW_NUMBER() over (partition by type , item order by modified desc) as ord
--,COUNT(*) over (partition by type,item) as num
--into #t2
-- from typeData
---- exclude list ...
---- where item not in (''rpt_getAccountPaymentTypes'',''rpt_getAccountPaymentTypes'',''rpt_getEmptyWeeklyTimesheet'')

--update typeData set active = case t.active when 1 then 0 else 1 end
--from typeData t
--join
--(
--select type,item from #t2
--where num > 2
--group by type,item
--having MAX(modind) = 1 and MAX(ord) = 2
--) as t2 on t2.item = t.item and t2.type = t.type

--drop table #t2

update t set active = 1 from upgTypeData u
join typeData t on t.item = u.item and t.type = u.type and t.id = u.id

update t set active = 0 from upgTypeData u
join typeData t on t.item = u.item and t.type = u.type and t.id <> u.id and t.active = 1

'
go

declare @s varchar(max) = 'UPGRADE SUCCESSFUL (DB version: 8340)' -- SET THIS ON BRANCH
exec logUpdate @s

set @s = 'UPGRADE SUCCESSFUL (DB sub version: 8.3.4)' -- SET THIS ON BRANCH TAG TO NEW VERSION --
exec logUpdate @s


select 'UPGRADE SUCCESSFUL',* from programsettings

go