set search_path to smart_solutions, public;

create table leads_clean(
	index int,
	lead_id text,
	created_date date,
	lead_source text,
	product_line text,
	region text,
	nam_owner text,
	client_type text,
	deal_value_usd float,
	period text,
	lead_status text,
	disqualified_reason text,
	is_deal_value_outlier boolean	
);

update leads_clean
set disqualified_reason = null
where disqualified_reason = '';

select count(*) from leads_clean where disqualified_reason is null;

create table opportunities_clean(
	opportunity_id text,
	lead_id text,
	opp_created_date date,
	product_line text,
	region text,
	nam_owner text,
	client_type text,
	deal_value_usd float,
	competitive_deal_flag boolean,
	used_fasttrack_approval boolean,
	period text,
	final_stage text,
	status text,
	status_reason text,
	closed_date	date
);

select count(*) from opportunities_clean limit 10;


create table won_deals_clean (
	opportunity_id text,
	lead_id text,
	product_line text,
	region text,
	nam_owner text,
	client_type text,
	deal_value_usd float,
	closed_date date,
	period text
); 

select count(*) from won_deals_clean limit 10;


create table stage_history_clean (
	opportunity_id text,
	stage text,
	entry_date date,
	exit_date date,
	days_in_stage int,
	period text
);

drop table stage_history_clean;


select count(*) from stage_history_clean limit 10;


-- Question - 1

/*
How many leads entered each stage? 
How many dropped off at each transition? 
What's the conversion rate at each step and end-to-end? 
Where is the single biggest drop-off?
*/

with total_leads as (
	select count(distinct lead_id) as total_leads, 
	sum(case when lead_status = 'Open' then 1 else 0 end) as open_leads,
	sum(case when lead_status = 'Disqualified' then 1 else 0 end) as disqualified_leads,
	sum(case when lead_status='Qualified' then 1 else 0 end) as qualified_leads
	from leads_clean
),
open_opps as (
	select
	count(distinct case when sh.stage = 'Qualify' then sh.opportunity_id end) as opps_qualify_stage,
	count(distinct case when sh.stage = 'Develop' then sh.opportunity_id end) as opps_dev_stage,
	count(distinct case when sh.stage = 'Propose' then sh.opportunity_id end) as opps_propose_stage,
	count(distinct case when sh.stage = 'Close' then sh.opportunity_id end) as opps_close_stage,
	count(distinct case when sh.stage = 'Close' and oc.status = 'Won' then sh.opportunity_id end) as opps_won
	from opportunities_clean oc
	join stage_history_clean sh on oc.opportunity_id = sh.opportunity_id
)
select
*,
opps_qualify_stage - opps_dev_stage as drop_in_qualify_stage,
opps_dev_stage - opps_propose_stage as drop_in_dev_stage,
opps_propose_stage - opps_close_stage as drop_in_propose_stage,
opps_close_stage - opps_won as drop_in_close_stage,
round((opps_qualify_stage * 100.0) / total_leads,2) as lead_to_qual_conv_rate,
round((opps_dev_stage * 100.0) / opps_qualify_stage,2) as qual_to_dev_conv_rate,
round((opps_propose_stage * 100.0) / opps_dev_stage,2) as dev_to_prop_conv_rate,
round((opps_close_stage * 100.0) / opps_propose_stage,2) as prop_to_close_conv_rate,
round((opps_won * 100.0) / opps_close_stage,2) as close_to_won_conv_rate,
round((opps_won * 100.0) / total_leads,2) as overall_conv_rate,
round((opps_qualify_stage - opps_dev_stage) * 100.0 / nullif(opps_qualify_stage, 0), 1) as pct_drop_at_qualify,
round((opps_dev_stage - opps_propose_stage) * 100.0 / nullif(opps_dev_stage, 0), 1)     as pct_drop_at_develop,
round((opps_propose_stage - opps_close_stage) * 100.0 / nullif(opps_propose_stage, 0), 1) as pct_drop_at_propose,
round((opps_close_stage - opps_won) * 100.0 / nullif(opps_close_stage, 0), 1)           as pct_drop_at_close
from total_leads tl
cross join open_opps oo;

/*
How many leads entered each stage? - Qualify - 1706, Develop - 1194, Propose - 829, Close - 174, Won - 80 
How many dropped off at each transition? - Drop in Qualify - 512, Drop in Develop - 365, Drop in Propose - 655, Drop in Close - 94
What's the conversion rate at each step and end-to-end? Lead to Qualify - 24%, Qualify to Develop - 70%, Dev to Propose - 70%, Propose to Close - 20%, Close to Won - 46%, Overall - 1% 
Where is the single biggest drop-off? - In Lead to Qualify - 2168 drops, In Propose stage - 655 drops 
*/


-- Question - 2

/*
 Loss reason breakdown for Propose-stage losses specifically. 
 Then segment it — by NAM, by product line, by region. 
 Does pricing dominate everywhere or only in certain segments?
*/

--2a

select status, final_stage, status_reason,
count(opportunity_id) as no_of_opps,
round(count(opportunity_id)*100.0 / sum(count(opportunity_id)) over (),2) as perc_opps
from opportunities_clean
where final_stage = 'Propose' and status = 'Lost'
group by status, final_stage, status_reason
order by no_of_opps desc;

select 
    competitive_deal_flag,
    status_reason                                               as loss_reason,
    count(opportunity_id)                                       as lost_opps,
    round(count(opportunity_id) * 100.0 / 
          sum(count(opportunity_id)) over (partition by competitive_deal_flag), 1) as pct_within_group
from opportunities_clean
where final_stage = 'Propose' 
  and status      = 'Lost'
group by competitive_deal_flag, status_reason
order by competitive_deal_flag, lost_opps desc;


-- 2b
with percentages as (select status, final_stage, region, product_line, status_reason,
count(opportunity_id) as no_of_opps,
round(count(opportunity_id)*100.0 / sum(count(opportunity_id)) over (partition by region, product_line),2) as perc_opps
from opportunities_clean
where final_stage = 'Propose' and status = 'Lost'
group by status, final_stage, region, product_line, status_reason 
order by region, product_line, no_of_opps desc)
select *, dense_rank() over(partition by region, product_line order by perc_opps desc)
from percentages;

-- 2c
with percentages as (
select status, final_stage,
nam_owner, status_reason,
count(opportunity_id) as no_of_opps,
round(count(opportunity_id)*100.0 / sum(count(opportunity_id)) over (partition by nam_owner),2) as perc_opps
from opportunities_clean
where final_stage = 'Propose' and status = 'Lost'
group by status, final_stage, nam_owner,  status_reason
order by nam_owner, no_of_opps desc)
select *, dense_rank() over(partition by nam_owner order by perc_opps desc) as ranks
from percentages;

/*
select lead_status, disqualified_reason, count(lead_id) as no_of_leads
from leads_clean
where lead_status = 'Disqualified'
group by lead_status, disqualified_reason
order by no_of_leads desc;
*/

/*
2a Competitive Deal Flag
- When there is competitive flag is false then 30% of opps lost due to 'Lost Contact' 
and 28% lost due to 'Budget Cut'.
- When the competitive flag is true then 43% lost due to Pricing and 29% due to 
Competitor Presence

2b

*/

with reached_propose as (
    select distinct opportunity_id
    from stage_history_clean
    where stage = 'Propose'
)
select
    oc.competitive_deal_flag,
    count(*)                                                    as reached_propose,
    sum(case when oc.status = 'Won'  then 1 else 0 end)        as won,
    sum(case when oc.status = 'Lost' 
             and oc.final_stage = 'Propose' then 1 else 0 end) as lost_at_propose,
    round(sum(case when oc.status = 'Won' then 1 else 0 end)
          * 100.0 / count(*), 1)                               as overall_win_rate_pct
from opportunities_clean oc
join reached_propose rp on oc.opportunity_id = rp.opportunity_id
group by oc.competitive_deal_flag;


/*
-- Nam Owners

S.Patel	Budget Cut and Lost Contact
D.Singh	Lost Contact 2nd reason
T.Chen	2nd reason - Budget Cut
Rest for all Pricing is the 1st reason for loss of opportunity	

-- Product Line and Region
Region	Top Reason	Exception
Midwest	Pricing Top 1 or 2 reason	Smart Mobility where Timeline Mismatch is the reason
Norteast	Pricing Top 1 or 2 reason	Smart Buildings where Budget Cut and then Lost Contact are the top 2 reasons
South	Pricing Top 1 or 2 reason	Smart Lightning where Competitor Presence and then Lost contact are the top reasons
West	Pricing Top 1 or 2 reason	Smart Lightning where Budget Cut (1) and Competitor Presence, Timeline Mismatch (2) are the top reasons
		
Question		"Out of all reasons - Pricing, Budget Cut, Competitor Presence, Timeline Mismatch, Lost Contact which are in our hands and can be controlled and what reasons we cannot control. 
According to me - Timeline Mismatch is somewhat in our control while Lost Contact is surely in our control."

*/


-- Question - 3

/*
What you need to answer: 
Win rate per NAM. But also — are the differences in win rate explained 
by the mix of competitive vs non-competitive deals they handle? 
A NAM with 80% competitive deals will naturally have a lower win rate 
than one with 20%. You need to show both the raw win rate and 
the competitive-adjusted picture.
*/

with lead_opps as (
	select lc.nam_owner, count(lc.lead_id) as total_leads, sum(case when oc.status = 'Won' then 1 else 0 end) as won_opps
	from leads_clean lc
	left join opportunities_clean oc on lc.lead_id = oc.lead_id
	group by lc.nam_owner
),
competitive_win_rates as (
    select
        nam_owner,
        round(sum(case when competitive_deal_flag = true  
                       and status = 'Won' then 1 else 0 end) * 100.0 /
              nullif(sum(case when competitive_deal_flag = true  
                              then 1 else 0 end), 0), 2)    as comp_win_rate,
        round(sum(case when competitive_deal_flag = false 
                       and status = 'Won' then 1 else 0 end) * 100.0 /
              nullif(sum(case when competitive_deal_flag = false 
                              then 1 else 0 end), 0), 2)    as non_comp_win_rate,
		sum(case when competitive_deal_flag = true 
                              then 1 else 0 end) as total_comp_deals,
		sum(case when competitive_deal_flag = false 
                              then 1 else 0 end) as total_non_comp_deals
    from opportunities_clean
    group by nam_owner
)
select lo.nam_owner, lo.total_leads, lo.won_opps, round(lo.won_opps*100.0 / nullif(lo.total_leads,0),2) as perc_win_rate,
cd.comp_win_rate, cd.non_comp_win_rate, cd.total_comp_deals, cd.total_non_comp_deals
from lead_opps lo
left join competitive_win_rates cd on lo.nam_owner = cd.nam_owner
order by perc_win_rate desc;

/*
For most of the NAM's high competitive rate means less win percentage.
But for S.Patel , the competitive rate is lowest yet his win percentage is 1.21% as compared
to R.Alvarez whose win_percentage is 1.51%
If i compare K.Romano with M.Okafor and D.Singh then they have almost same competitive deal_rate 
of 48-49% even then there perc_win_rate is lower than him.
For T.Chen, she has slightly lower competitive rate than R.Alvarez but her perc_win_rate is 
0.93% while R.Alvarez is 1.51%.
*/

-- Updating using joins in Postgres
-- UPDATE leads_clean l
-- SET nam_owner = o.nam_owner
-- FROM opportunities_clean o
-- WHERE l.lead_id = o.lead_id
--   AND l.nam_owner = 'Unassigned';

select nam_owner, competitive_deal_flag, status, count(*) 
from opportunities_clean
where nam_owner = 'T. Chen'
group by nam_owner, competitive_deal_flag, status
order by competitive_deal_flag, status;

/*
Yes there are 0 wins for Chen when competitive_deal_flag is false.
It could be that here non-competitive deals are still open and in pipeline.
*/

select 
    nam_owner,
    competitive_deal_flag,
    status_reason,
    count(*) as lost_deals,
    round(count(*) * 100.0 / 
          sum(count(*)) over (partition by nam_owner, competitive_deal_flag), 1) as pct
from opportunities_clean
where status = 'Lost'
  and nam_owner in ('S. Patel', 'T. Chen', 'M. Okafor', 'D. Singh')
group by nam_owner, competitive_deal_flag, status_reason
order by nam_owner, competitive_deal_flag, lost_deals desc;

/*
D.Singh - competitive_flag = false - Lost Contact top reason
	    - competitive_flag = true - Pricing is the top reason
M.Okafor - competitive_flag = false - Budget Cut top reason and then Lost Contact
	     - competitive_flag = true - Budget Cut & Pricing are the top reasons
S.Patel  - competitive_flag = false - Budget Cut top reason and then Lost Contact
	     - competitive_flag = true - Pricing & Competitor Presence are the top reasons
T.Chen  - competitive_flag = false - Budget Cut top reason and then Lost Contact
	     - competitive_flag = true - Pricing, Budget Cut & Lost Contact are the top reasons
*/


-- Question - 4

/*
For each lead source — leads generated, opportunities created, 
deals won, end-to-end conversion rate, and total revenue won. 
Rank by revenue, not by lead volume.
*/

with lead_source_summ as (
	select l.lead_source, count(l.lead_id) as total_leads,
	count(o.opportunity_id) as total_opps,
	sum(case when o.status = 'Won' then 1 else 0 end) as won_opps,
	round((sum(case when o.status = 'Won' then 1 else 0 end)*100.0)/count(l.lead_id),2) as end_to_end_conv_rate,
	sum(case when o.status = 'Won' then o.deal_value_usd else 0 end) as total_revenue
	from leads_clean l
	left join opportunities_clean o on l.lead_id = o.lead_id
	group by l.lead_source
)
select *, dense_rank() over(order by total_revenue desc) as revenue_rank,
round(total_revenue/ nullif(total_leads, 0)) as revenue_per_lead,
round(total_revenue/ nullif(won_opps, 0)) as avg_deal_size_opp,
round(total_opps * 100.0 / total_leads, 2) as lead_to_opp_conv_rate,
round(won_opps * 100.0 / total_opps, 2) as opp_to_win_conv_rate,
dense_rank() over(order by round(total_revenue/ nullif(total_leads, 0)) desc) as revenue_per_lead_rank
from lead_source_summ
order by revenue_per_lead_rank;

/*

**The three findings to present:**

**Finding 1 — Existing Client Upsell is the highest-quality source, not the highest-volume one.**
Rs. 542 revenue per lead, Rs. 40,128 average deal size on won deals — both highest of any source. 
Only 963 leads generated, which is why it ranks 3rd on total revenue. 
This source is under-invested. The recommendation: dedicate more NAM time to existing account expansion, 
which in B2B IoT means going back to clients who already bought Smart Cameras and selling them EV Charging 
or Smart Lighting. The trust is already established — that's why conversion rate (1.35%) and deal size are both higher.

**Finding 2 — Partner Referral punches above its weight.**
Same 1.35% conversion rate as Existing Client Upsell, second-highest revenue per lead at Rs. 404, 
and 5.7% opp-to-win rate — the highest of any source. 
Partner-referred deals close at nearly twice the rate of Trade Show leads (5.7% vs 4.3%) because 
they arrive with a warm introduction and pre-established credibility. 
Recommendation: invest in partner channel development — more certified resellers, better partner incentive structure.

**Finding 3 — Trade Show is the worst-performing source by every efficiency metric.**
Lowest revenue per lead (Rs. 185), lowest average deal size won 
(Rs. 19,082 — less than half of Existing Client Upsell), 0.97% conversion rate, 
and 4.3% opp-to-win rate. Yet Trade Shows require significant upfront investment in booth costs, t
ravel, and staff time. The recommendation is not necessarily to eliminate Trade Shows — 
they may serve brand awareness purposes — but to be honest that as a revenue-generation channel, 
the data does not justify the cost relative to alternatives.

**Finding 4 — Cold Outreach is surprisingly efficient for its volume.**
Only 437 leads (smallest source), but Rs. 300 revenue per lead and Rs. 32,738 average deal size —
similar to Inbound Web Form at Rs. 32,480. With a structured SDR process and better targeting, 
this source could scale.

---

**The recommendation slide for this brief:**

*"Ranked by total revenue, Inbound Web Form and Outbound SDR appear to be our best channels. 
But when adjusted for efficiency (revenue per lead), Existing Client Upsell and Partner Referral 
are significantly stronger — they generate more revenue per investment unit, at higher deal sizes, 
with better close rates. We recommend reallocating 15-20% of SDR capacity from cold outreach to
account expansion and partner development, and evaluating Trade Show ROI against alternative 
uses of that budget."*

---

Now write Brief 5 — the fast-track before/after comparison. 
This is the most important query in the project because it produces the number 
that goes in your resume bullet. Think carefully about your table structure: 
you need P1 baseline, P2 fast-track used, and P2 fast-track not used as your 
three comparison groups. Write it and share.
*/


-- Question - 5

/*
Win rate for competitive deals in P1 vs P2 where fast track was used and where fast track was not used in 2025.
*/

select period, competitive_deal_flag, used_fasttrack_approval, sum(case when status = 'Won' then 1 else 0 end) as won_opps, 
sum(case when status = 'Lost' then 1 else 0 end)               as lost_opps,
count(opportunity_id) as total_opportunities,
round(sum(case when status = 'Won' then 1 else 0 end) * 100.0 / count(opportunity_id), 2) as win_rate 
from opportunities_clean
where competitive_deal_flag = true
group by period, competitive_deal_flag, used_fasttrack_approval;

select period, competitive_deal_flag, sum(case when status = 'Won' then 1 else 0 end) as won_opps, 
sum(case when status = 'Lost' then 1 else 0 end)               as lost_opps,
count(opportunity_id) as total_opportunities,
round(sum(case when status = 'Won' then 1 else 0 end) * 100.0 / count(opportunity_id), 2) as win_rate 
from opportunities_clean
group by period, competitive_deal_flag
order by 1,2;



-- Question - 6

/*
Average and median days at Propose stage for Won vs Lost deals.
*/

select o.status, avg(s.days_in_stage) as avg_days_in_propose,
percentile_disc(0.5) within group(order by s.days_in_stage) as median_days_in_propose
from opportunities_clean o
join stage_history_clean s on o.opportunity_id = s.opportunity_id
where s.stage = 'Propose'
group by o.status;

/*
Then bucket deals by days-at-proposal (0-7 days, 8-14, 15-21, 22-30, 30+) and show win rate per bucket. 
This gives you the intervention threshold — the point at which the win rate drops sharply 
enough to trigger a manager check-in.
*/

with buckets as (
	select s.opportunity_id, s.days_in_stage, 
	case when o.status = 'Won' then 1 else 0 end as ind_won,
	case when s.days_in_stage < 8 then 'a. 0-7 days'
	when s.days_in_stage < 15 then 'b. 8-14 days'
	when s.days_in_stage < 22 then 'c. 15-21 days'
	when s.days_in_stage < 31 then 'd. 22-30 days'
	else 'e. 30+ days' end as bucket
	from stage_history_clean s 
	join opportunities_clean o on s.opportunity_id = o.opportunity_id
	where stage = 'Propose'
)
select bucket, sum(ind_won), count(distinct(opportunity_id)), round(sum(ind_won) * 100.0 / nullif(count(opportunity_id),0),2) as win_rate
from buckets
group by bucket
order by bucket;


-- product_line vs deal_value_usd_won
select l.product_line, count(l.lead_id) as total_leads, 
count(o.opportunity_id) as total_opps,
count(case when o.status = 'Won' then o.opportunity_id end) as won_opps, 
sum(case when o.status = 'Won' then o.deal_value_usd else 0 end) as deal_value_usd_won,
round(sum(case when o.status = 'Won' then o.deal_value_usd else 0 end)::numeric / count(case when o.status = 'Won' then o.opportunity_id end)::numeric,2) as avg_rev_per_won_opp
from leads_clean l
left join opportunities_clean o on l.lead_id = o.lead_id
group by l.product_line
order by deal_value_usd_won desc;

-- there are no open opps in the data


CREATE VIEW opp_stage_detail AS
SELECT 
    o.opportunity_id, o.lead_id, o.nam_owner, o.region,
    o.product_line, o.competitive_deal_flag,
    o.used_fasttrack_approval, o.status, o.final_stage,
    o.deal_value_usd, o.period,
    s.stage, s.entry_date, s.exit_date, s.days_in_stage
FROM opportunities_clean o
JOIN stage_history_clean s ON o.opportunity_id = s.opportunity_id;

select * from opp_stage_detail;

-- win rate per nam owner

select nam_owner, 
count(case when status = 'Won' then opportunity_id end) as total_wins,
count(opportunity_id) as total_opps,
round(count(case when status = 'Won' then opportunity_id end) * 100.0 / count(opportunity_id),2) as win_rate,

from opportunities_clean
group by nam_owner
order by win_rate;