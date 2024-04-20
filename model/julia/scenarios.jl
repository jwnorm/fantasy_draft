### A Pluto.jl notebook ###
# v0.19.40

using Markdown
using InteractiveUtils

# ╔═╡ 7d4d5798-fac3-11ee-0020-a3bc46fa36d2
 using JuMP, HiGHS, CSV, DataFrames, OrderedCollections

# ╔═╡ a7af3923-1317-49f9-bbc2-dc8f3b735aa5
md"""
# Fantasy Baseball Draft - Scenario Analysis
**Jacob Norman**
"""

# ╔═╡ 4c6fe46b-1c25-4f9a-bd88-63ffb7e84a39
md"""
## Introduction

This report will build on the previous analysis that established a base optimal fantasy baseball roster and analyze the effects that altering different inputs have on the result.

Here are broad areas where we will investigate changes:

* Projection system utilized
* Punting one or more categories
* Proxy for player draft value
* Starting draft position
* Strict vs relaxed goal bounds
"""

# ╔═╡ adf90438-b24e-4e80-8ceb-b47ca2f3a67d
md"""
## Preprocessing

To begin, we will load the required libraries.
"""

# ╔═╡ a124c6c7-dcc2-4243-bf38-a4229b902be4
md"""
It is also necessary to specify our targets by category and the required number of players on the roster who are eligible for each position. This is taken from our previous analysis.
"""

# ╔═╡ b91d11e0-dcf4-4e17-bd85-1e4de7e91278
begin
	targets = OrderedDict("HR" => 275, 
						  "R" => 1000, 
						  "RBI" => 1000, 
						  "SB" => 200, 
						  "OBP" => 0.35 * 13,
						  "W" => 100, 
						  "SOLD" => 75,
						  "SO" => 1200,
						  "WHIP" => 1.2 * 10,
						  "ERA" => 3.7 * 10)
	
	position_min = OrderedDict("C" => 1, 
							   "1B" => 1, 
							   "2B" => 1, 
							   "3B" => 1, 
							   "SS" => 1, 
							   "INF" => 1 + 4,  # added 4 for other INF reqs
							   "OF" => 4, 
							   "UT" => 1 + 10,  # added 10 for position player reqs
							   "P" => 7)

end

# ╔═╡ 8b8911bd-8048-499b-915b-43f820ccf29c
md"""
Next, we need to actually run our optimization model. Rather than repeat the previous report that walks through each individual step in detail, we will collect all of them in a single function. This will help facilitate quickly iterating through multiple different scenarios.

> **Note:** If you would like a refresher on what each formula means, check out the [prior analysis](https://github.com/jwnorm/fantasy_draft/blob/main/model/julia/base.html).

We will start by creating some helper functions to use in our main function, which we will call `fantasy_draft`.
"""

# ╔═╡ e2439dac-168d-4e99-a1f7-e377e71ed104
"""
This function reads in the desired projection csv file as a DataFrame and creates a new column for `SOLD`s.

Arguments

- `path::String`: The file path of the folder where the csv file is located
- `system::String`: The projection system used: zips, steamer, atc, bat, batx_atc 

Returns   

`df::DataFrame`: The projection system df
"""
function read_projection_df(path::String, system::String)
	# read in df
	df = DataFrame(CSV.File("$path$system.csv"))
	
	# create SOLD col
	df[:, :SOLD] = df[:, :SV] .+ df[:, :HLD]

	# create draft position cols
	df[:, :HighDP] = df[:, :ADP] * 1.15
	df[:, :LowDP] = df[:, :ADP] * 0.85
	
	return df
end

# ╔═╡ ca2c2ce7-3ee3-4c0d-8852-7d8d24757906
"""
This function actually solves the integer programming model for the fantasy baseball draft.

Arguments

- `targets::OrderedDict{String, Real}`: A dictionary of the categories and their corresponding target
- `positions::OrderedDict{String, Int64}`: A dictionary of the roster positions and the minimum number of eligible players for each one
- `strict_goal::Bool`: Whether or not to force the model to meet the minimum targets
- `projections::String`: The projection system used: zips, steamer, atc, bat, batx_atc 
- `draft_value::String`: The proxy for player draft value: ADP, MinDP, MaxDP, LowDP, HighDP
- `start_position::Int64`: Starting draft position in round 1

Returns   

- `x::Any`: Model results
- `m::Int64`: The number of rounds in the draft
- `weights::OrderedDict{String, Int64}`: A dictionary of all 10 categories and the direction of improvement, -1 or +1
"""
function solve_model(targets::OrderedDict{String, Real},
					 positions::OrderedDict{String, Int64},
					 strict_goal::Bool,
					 projections::String,
					 draft_value::String,
					 start_position::Int64)

	# read in projection df
	df = read_projection_df("../../data/", projections)

	# initialize model
	model = Model(HiGHS.Optimizer)
	set_silent(model)

	# sets
	n = length(df[:, :player])
	m = 25
	negative_categories = ["WHIP", "ERA"]
	positive_categories = [i for i ∈ keys(targets) if i ∉ negative_categories]


	# parameters
	teams = 12

	weights = OrderedDict("HR" => 1, 
				   		  "R" => 1, 
				   		  "RBI" => 1, 
				   		  "SB" => 1, 
				   		  "OBP" => 1,
				          "W" => 1, 
					      "SOLD" => 1,
				          "SO" => 1,
			              "WHIP" => -1,
				          "ERA" => -1)


	# decision variable
	@variable(model, x[df[:, :player], 1:m], Bin)

	# goal expression
	@expression(model, 
				obj[k ∈ keys(targets)], 
				((sum(x[df[i, :player], j] * df[i, k] 
				for i=1:n, j=1:m) - targets[k]) / targets[k]))

	# objective function
	@objective(model, Max, sum(weights[k] * obj[k] for k ∈ keys(targets)))

	# constraints
	@constraint(model,
				round_max[j ∈ 1:m], 
				sum(x[:, j]) == 1)
	
	@constraint(model, 
				player_max[i ∈ df[:, :player]], 
				sum(x[i, :]) <= 1)

	if start_position == 1
		@constraint(model, 
					adp_odd_max[j ∈ 1:2:m], 
					sum(df[i, draft_value] * x[df[i, :player], j] 
					for i=1:n) >= teams * (j - 1) + start_position)
		
		@constraint(model, 
					adp_even_max[j ∈ 2:2:m], 
					sum(df[i, draft_value] * x[df[i, :player], j] 
					for i=1:n) >= teams * j)
		
	elseif start_position == 6 
		@constraint(model, 
					adp_odd_max[j ∈ 1:2:m], 
					sum(df[i, draft_value] * x[df[i, :player], j] 
					for i=1:n) >= teams * (j - 1) + start_position)

		@constraint(model, 
					adp_even_max[j ∈ 2:2:m], 
					sum(df[i, draft_value] * x[df[i, :player], j] 
					for i=1:n) >= teams * (j - 1) + start_position + 1)

	elseif start_position == 12
		@constraint(model, 
					adp_odd_max[j ∈ 1:2:m], 
					sum(df[i, draft_value] * x[df[i, :player], j] 
					for i=1:n) >= teams * (j - 1) + start_position)
		
		@constraint(model, 
					adp_even_max[j ∈ 2:2:m], 
					sum(df[i, draft_value] * x[df[i, :player], j] 
					for i=1:n) >= teams * (j - 2) + start_position + 1)
	end

	@constraint(model, 
				pos_min[p ∈ keys(position_min)], 
				sum(df[i, p] * x[df[i, :player], j] for i=1:n, j=1:m) >= position_min[p])

	if strict_goal
		@constraint(model, positive_goal[k ∈ positive_categories], obj[k] >= 0)
		@constraint(model, negative_goal[k ∈ negative_categories], obj[k] <= 0)
	end

	# solve model
	optimize!(model)

	# return optimal x values and number of draft rounds
	return x, m, weights
end

# ╔═╡ 08151864-5f70-4870-8e7a-ad51490b70b4
"""
This function filters the original projections DataFrame to only include selected players and sort by draft order.


Arguments

- `df::DataFrame`: Original projections DataFrame
- `dv::Any`: Decision variables; what player is selected by the model in each round
- `m::Int64`: The number of rounds in the draft

Returns   

`roster_df::DataFrame`: DataFrame of only drafted players sorted in ascending draft order
"""
function get_roster(df::DataFrame, dv::Any, m::Int64)

	# initialized all players with 0
	roster = OrderedDict(i => 0 for i ∈ df[:, :player])

	# assign round to players that were drafted
	for j ∈ 1:m, i ∈ df[:, :player]
	    if round(value(dv[i, j])) == 1
			roster[i] = j
		end
	end
	
	# add round to df
	df[:, :round] = [roster[i] for i ∈ df[:, :player]]

	# create new df
	roster_df = filter(:round => >=(1), df)
	sort!(roster_df, order(:round))

	return roster_df
end

# ╔═╡ 51046ed3-195d-4e2d-be12-96e2348ac7fe
"""
This generates multiple arrays related to the model solution to faciliate scenario analysis.


Arguments

- `df::DataFrame`: DataFrame of drafted players in ascending draft order
- `weights::OrderedDict{String, Int64}`: A dictionary of all 10 categories and the direction of improvement, -1 or +1
- `position_min::OrderedDict{String, Int64}`: A dictionary of the roster positions and the minimum number of eligible players for each one

Returns   

- `roster::Array{String, 1}`: List of selected players in draft order
- `stats::Array{Real, 1}`: List of total teams statistics in category order
- `positions::Array{Int64, 1}`: List of total players eligible for a position in position order
"""
function generate_output(df::DataFrame, 
						weights::OrderedDict{String, Int64}, 
						position_min::OrderedDict{String, Int64})

	# determine roster
	roster = df[:, :player]
	
	# create stats array
	stats = [sum(df[:, k]) for k ∈ keys(weights)]
	total_hitters = sum(df[:, :UT])
	total_pitchers = sum(df[:, :P])

	stats[5] = stats[5] / total_hitters  # adjust OBP from total to avg
	stats[[9, 10]] = stats[[9, 10]] / total_pitchers  # adjust WHIP/ERA from total to avg

	# create position array
	positions = [sum(df[:, p]) for p ∈ keys(position_min)]

	return roster, stats, positions
end

# ╔═╡ 789e86f3-c4ca-4a0c-9974-5079468881c1
"""
Full program for running a single integer programming model and outputting the results for the fantasy baseball draft problem.


Arguments
- `targets::OrderedDict{String, Real}`: A dictionary of the categories and their corresponding target
- `positions::OrderedDict{String, Int64}`: A dictionary of the roster positions and the minimum number of eligible players for each one
- `strict_goal:: Bool`: Whether or not to force the model to meet the minimum targets
- `projections::String`, optional: The projection system used: zips, steamer, atc, bat, batx_atc; default is "batx_atc"
- `draft_value::String`, optional: The proxy for plasyer draft value: ADP, MinDP, MaxDP, LowDP, HighDP; default is "ADP"
- `start_position::Int64`, optional: Starting draft position in round 1; default is 12
- `print::Bool`, optional: Whether or not to print the roster in draft order to the sceen; default is true
- `export_arrays::Bool`, optional: Whether or not to return arrays relating to the roster, team statistics, and player positions; default is false

Returns   

- `roster::Array{String, 1}`: List of selected players in draft order
- `stats::Array{Real, 1}`: List of total teams statistics in category order
- `positions::Array{Int64, 1}`: List of total players eligible for a position in position order
"""
function fantasy_draft(targets::OrderedDict{String, Real},
					   positions::OrderedDict{String, Int64},
					   strict_goal::Bool=true;
					   projections::String="batx_atc", 
					   draft_value::String="ADP",
					   start_position::Int64=12,
					   print::Bool=true, 
					   export_arrays::Bool=false)

	# read in projection df
	df = read_projection_df("../../data/", projections)

	# solve model
	x, m, weights = solve_model(targets, positions, strict_goal, 
								projections, draft_value, start_position)

	# get roster
	roster_df = get_roster(df, x, m)

	# if true, print roster
	if print
		show(select(roster_df, :player), allrows=true)
	end
	
	# if true, export output arrays
	if export_arrays
		roster, stats, positions = generate_output(roster_df, weights, position_min)
		return roster, stats, positions
	end
end

# ╔═╡ b08ca88d-9e21-46d4-8d1f-fc16df6905e3
md"""
## Base Case

To begin, let's review the base case from the previous analysis. As a reminder, this uses *THE BAT X* projections for batters and *ATC* projections for pitchers.
"""

# ╔═╡ e847c6fb-2df7-4e46-bcdd-0352babf7826
fantasy_draft(targets, position_min)

# ╔═╡ d7da5063-6824-4b79-a3af-3d25dfe5f4ea
md"""
**When I reference the base model throughout this report, this is the cohort of players it corresponds to.**

We know from our previous analysis that we hit all of our targets except on base percentage. Some other interesting notes on this roster:

* The model targets starting pitching early and often. This actually goes against current popular draft strategies. The pitchers it drafted are projected to be leading in innings pitched, which will drive strikeouts and wins. In addition, the first four starters are all aces which will generally mean good ratios as well.

* Next, the model selected several relief pitchers, which are the only source of saves and holds. This category is a difficult one to accurately predict, so grabbing someone that projects for a lot of `SOLD`s can generally only be accomplished early in the draft.

* For position players, the model selected what I will call "oatmeal" players. These are generally established veterans who are a known quantity: there is very little upside here. I suspect the model is targeting them because their draft value is not in line with their expected production. This is because these players can be seen as boring.
"""

# ╔═╡ 5b71337e-2b99-4d37-9499-896f079e60ae
md"""
## Projection System

Now let's see how the projection system used impacts the final roster and the overall category totals. There are several systems we will utilize:

* *ZiPS*
* *Steamer*
* *ATC*
* *THE BAT*

Since the objective function and related expressions are heavily dependent on the projection system used, I suspect the rosters will vary wildly.

To help our analysis, we will need a helper function. There are several scenarios we would like to work through, so we can take advantage of Julia's *multiple dispatch* capabilities to create one function that does slightly different things depending on the types of the input parameters.
"""

# ╔═╡ ef26e745-741f-4d93-a5df-e9cf84966cfb
projections = ["batx_atc", "zips", "steamer", "atc", "bat"]

# ╔═╡ 0a8f41f7-c29f-46ce-bce5-93a5b0d6115b
"""
# Projection Scenario

This function iterates through a list of projection systems and compares the subsequent model results.

Arguments
- `targets::OrderedDict{String, Real}`: A dictionary of the categories and their corresponding target
- `position_min::OrderedDict{String, Int64}`: A dictionary of the roster positions and the minimum number of eligible players for each one
- `projections::Array{String, 1}`: List of projection systems to be compared

Returns   

- `roster_df::DataFrame`: DataFrame where each column is the roster in draft order for a scenario
- `stats_df::DataFrame`: DataFrame where each column is the team category totals
- `positions_df::DataFrame`: DataFrame where each column is number of players by position for each scenario
"""
function run_scenario_analysis(targets::OrderedDict{String, Real},
							   position_min::OrderedDict{String, Int64},   
							   projections::Array{String, 1})

	# initialize empty roster df
	roster_df = DataFrame()
	
	# initialize stats df and add targets
	stats_df = DataFrame(Category = [k for k ∈ keys(targets)],
						 Target=[targets[k] for k ∈ keys(targets)])

	# convert ratio targets from sum to avg
	stats_df[5, :Target] = stats_df[5, :Target] / 13
	stats_df[[9, 10], :Target] = stats_df[[9, 10], :Target] / 10

	# initialize positions df and add targets
	positions_df = DataFrame(Position = [p for p ∈ keys(position_min)],
	Target=[position_min[p] for p in keys(position_min)])

	# loop through scenarios and create new column in all dfs
	for system ∈ projections
		roster, stats, positions = fantasy_draft(targets, position_min; 
		projections=system, print=false, export_arrays=true)
	
		roster_df[:, system] = roster
		stats_df[:, system] = stats
		positions_df[:, system] = positions
	end

	return roster_df, stats_df, positions_df
end

# ╔═╡ 095f7ad1-8e74-4f2c-954a-7db24133680a
md"""
Interestingly, there is a lot of commonality between the five different projections! The two most different rosters are the ones sourced from the *ZiPS* and *Steamer* projections.

Overall, almost all models place a premium on starters and relievers and end up taking batters in the middle to late rounds. Also, a lot of those hitters end up being one-category players. An example is Esteury Ruiz, who offers a ton of speed, and therefore stolen base potential, but not much else.

Here are some thoughts on each system.

### *ZiPS*
This is by far the most unique draft the model ended up selecting and what I would consider most similar to a real-life draft scenario. The first pick is Elly De La Cruz, an electric power-speed combo bat who had a lot of hype going into the 2024 season. Like some of the other models, the next several picks are all pitchers; however, there are some high-ceiling options, such as Yoshinobu Yamamoto, not present in the others.

Again, we have some players that excel at one category: Kyle Schwarber (`HR`), Esteury Ruiz (`SB`), and Cedric Mullins (`SB`). It seems that there *is* a player profile that *ZiPS* is very bullish on: rookies with top prospect pedigree. This makes up a good portion of the roster, including: Jackson Chourio, Ceddanne Rafaela, Jasson Dominguez, Victor Scott II, and Pete Crow-Armstrong.

### *Steamer*
This one has a similar strategy as our base model; however, the pitchers it chooses are different. This is likely because as a projection system with different inputs, the performance it expects of each player can be very different. *Steamer* prefers Kevin Gausman as the top pitcher over Zack Wheeler because Gausman is projected for more strikeouts in this model.

The base strategy is generally risk adverse; however, the *Steamer* model does select a few players with risk in their profile: Grayson Rodriguez, Mason Miller, Carlos Rodon, and Anthony Rendon. Rodriguez is a second year player who only started to click in the second half of last year, while Rendon and Rodon are both injury risks. Miller is a mix of both, as an injury severely limited his first year in the big leagues in 2023. The model is likely capitalizing on the discrepency between projected player value and actual draft value that comes from perceived issues by the fantasy community.

### *ATC*
This model uses the same pitching projections as the base model, so the differences on that side are pretty minimal. The first four selections are exactly the same, but curiously, there are some differences in other pitchers. As an example, the *ATC* model selects Logan Gilbert in the fifth round, while the base model takes a reliever. This must be due to hitters that are selected later in the draft, which are a little different than the base model.

This model added a lot of position players that can contribute to more than one category, but generally excel at two: Jonathan India (`HR` & `OBP`), Jack Suwinski (`HR` & `SB`), and Jake Fraley (`HR` & `SB`). Interestingy, these players are all taken near the end of the draft, while there are more premium hitters early on that the model passes on in favor of pitching. This tells me that pitching stats are harder to come by, while offensive stats can be made up in the final few rounds.

### *THE BAT*

While the name sounds similar to *THE BAT X*, there is a subtle but major difference: *THE BAT X* uses Statcast data while *THE BAT* does not. One advantage of this is that it can project for pitchers as well.

There are a few pitchers that *THE BAT* likes more than the base case: Max Fried, Pablo Lopez, Dylan Cease, Hunter Brown, and Nestor Cortes. These guys do have more risk inherent in their profile, whether it be injury, experience, or performance. *THE BAT* clearly is projecting all of them to rebound, which the model is exploiting here.

From a hitters perspective, many of the same players are selected, and those that are different have similar projected stats as those who are left out. An example is, Jonathan India over Jeremy Pena. They are both solid defenders who have had some volatility while providing a balanced bat.

Moving on, let's see how the team stats looks for each model:
"""

# ╔═╡ 4e9f2530-7055-4ba2-a8a8-81497f3e5efe
md"""
It is easy to see where the bottleneck is: clearly wins are hard to come by since no model has more than the minimum target. Wins are difficult to project since they are not entirely driven by individual player performance and can therefore be more random.

Four of the models are pretty similar: base case, *Steamer*, *ATC*, and *THE BAT*. I would say they are all fairly well-balanced teams that tend to favor one or two categories more than the other models. *Steamer* has more `RBI`s and strikeouts. *THE BAT* is weakest in `SOLD`s, but has the most home runs and the lowest `WHIP` of the group. The base model leans toward stolen bases. *ATC* is seemingly the most well-rounded. This makes sense since it is an average of the other projection systems (plus others not included).

*ZiPS* is clearly the outlier here so I want to highlight it. It projects for exactly target home runs, but over 150 more stolen bases and almost double the `SOLD`s compared to the target! These categories can be some of the trickiest to build a team around, so I am surpised with the surplus the model has. It does have the lowest projected strikeouts, but has the best pitching ratios of any model.

Why is this model's roster so different? Well, it comes down to how the projections are built. *ZiPS* is based off of simulated seasons, while the other models are some form of regression. This allows *ZiPS* to factor in more upside, which is why the model selected so many young players. They have the potential to explode.

Let's also look at the positional eligibility of the rosters:
"""

# ╔═╡ ef7b348e-f4d9-4296-a877-a6e55dbd7faa
md"""
All models selected 15 hitters and 10 pitchers. Additionally, some similar themes start to emerge: all rosters have one catcher, and there is a surplus of outfield-eligible players. This makes sense because catchers typically do not offer a ton of value with their bat when compared to other positions, so there is no need to draft more than one. Conversely, the outfield is generally where a lot of the talented hitters end up playing since it requires the least amount of defensive ability (center fielders--please forgive me for that generalization!).
"""

# ╔═╡ 97ce6cd2-4763-4d0f-99bd-15ad38995c31
md"""
## Draft Value

Next, we will investigate adjusting the draft value of players. This will determine how late a player is available and, therefore, the latest round they can be selected.

By default, we chose to use **A**verage **D**raft **P**osition (`ADP`) as a proxy for player value, but how does our model change if we use the latest draft position (which I am calling `MaxDP`)? We will also look at a couple other cases: 

* `HighDP` will feature `ADP` values raised by 15 percent
* `LowDP` will reduce `ADP` by 15 percent

We will modify our helper function to accomplish this.
"""

# ╔═╡ b77c387d-872a-466c-a8c6-427f76494349
draft_values = ["ADP", "LowDP", "HighDP", "MaxDP"]

# ╔═╡ ce5a4b0a-7bca-48ec-9c02-2e29bd83fd6c
"""
# Draft Value Scenario

This function iterates through a list of player draft valuations and compares the subsequent model results.

Arguments
- `targets::OrderedDict{String, Real}`: A dictionary of the categories and their corresponding target
- `draft_values::Array{String, 1}`: List of player draft valuation systems to be compared

Returns   

- `roster_df::DataFrame`: DataFrame where each column is the roster in draft order for a scenario
- `stats_df::DataFrame`: DataFrame where each column is the team category totals for a scenario
"""
function run_scenario_analysis(targets::OrderedDict{String, Real}, 
							   draft_values::Array{String, 1})

	# initialize empty roster df
	roster_df = DataFrame()
	
	# initialize stats df and add targets
	stats_df = DataFrame(Category = [k for k ∈ keys(targets)],
						 Target=[targets[k] for k ∈ keys(targets)])

	# convert ratio targets from sum to avg
	stats_df[5, :Target] = stats_df[5, :Target] / 13
	stats_df[[9, 10], :Target] = stats_df[[9, 10], :Target] / 10


	# loop through scenarios and create new column in all dfs
	for system ∈ draft_values
		roster, stats = fantasy_draft(targets, position_min; 
		draft_value=system, print=false, export_arrays=true)
	
		roster_df[:, system] = roster
		stats_df[:, system] = stats
	end

	return roster_df, stats_df
end

# ╔═╡ e3202458-11ae-40a0-90ce-21d1720b536d
md"""
### `LowDP`
In our previous analysis we noted that there were several "high-risk" players, meaning they were selected very close to their `ADP`. Looking at this first scenario, one of those players did not get drafted at all: Camilo Doval. The other three players were all drafted in earlier rounds. For example, Kyle Schwarber was taken in round 6 instead of round 8. Otherwise, the rosters are very similar, which makes sense given the fact that the base model was selecting players much earlier than their `ADP` in most cases.

### `HighDP`
This scenario increased the players `ADP` by 15 percent, which allowed the model slightly more flexibilty. In the first round, Shohei Ohtani is now able to be selected. Coming off an MVP season, his bat will surely provide massive boosts to all offensive categories. Also, the `HighDP` model selects one additional pitcher and exchanges one for another, resulting in the additions of Kevin Gausman and Max Fried. This forces the model to take two B-level closers a few rounds later, Andres Munoz and Clay Holmes. The only other difference is that a couple one-dimensional players are drafted in the `HighDP` model: Esteury Ruiz (`SB`) and Christopher Morel (`HR`).

### `MaxDP`
By increasing the last position that a given player can be drafted, we effectively lowered the value of each player in the draft. An obvious consequence is that the roster we end up with is filled with higher-quality players. Spencer Strider is considered the top fantasy baseball pitcher in 2024, and we are able to draft him in the first round with his reduced cost. Otherwise, a lot of the same pitchers are taken in the draft, just in later rounds.

> **Note:** Unfortunately, Strider had season-ending elbow surgery after his first two starts of the 2024 season. This underscores the importance of incorporating injury risk into models such as this; however, most projection systems do not have this risk fully baked into the numbers.

An interesting note is that the overall draft strategy in the first four rounds changes dramatically. We actually take position players in rounds 2 and 4: Fernando Tatis Jr. and Randy Arozarena. Tatis is considered a five category guy, and so is Arozarena to a lesser extent. This creates a solid foundation to build upon in the remaining rounds.

Matt Chapman is drafted in almost the exact same position, which implies that he is an exceptional value when using `ADP` as a proxy for market sentiment.

Let's take a look at how the team stat totals look with the new teams:
"""

# ╔═╡ 107f7761-75f5-4928-b47a-051e82a45e1d
md"""
With the `LowDP` model, most stats are fairly close to the base case other than `SB`, `OBP`, and `SOLD`s. This is not surprising given that both rosters are pretty similar. The drop in `OBP` is likely driven by the final several selections that prioritize power. As an example, Jose Abreu and Eugenio Suarez are boom or bust power guys, while Javier Baez has terrible plate discipline.

The `HighDP` scenario has improved or similar stats in all categories. The standout for me are the pitching ratios `WHIP` and `ERA`, which are better than even the `MaxDP` model. The pitching in this model is truly elite while maintaining strong counting stats. The `MaxDP` model neglects starting pitching early on while `HighDP` takes a premium bat and then goes all-in on starters and relievers for several rounds. This is what is driving that difference.

As expected, every single stat in the `MaxDP` model remained the same or is improved. Wins stayed the same at 100, which is further evidence that that contraint is really limiting the upside in other categories. Plus, even with taking the top pitcher on one of the top teams in the MLB, we are still just barely hitting our targeted win total.

Of course, this scenario is not realistic. A player might be selected near their maximum draft position occasionally, but this would be an unreasonable assumption to make for every player. Indeed, even going off of `ADP`, while better, is still not an entirely reasonable as many players will be taken prior to this number. 

> **Note:** I ran a scenario that used player values based on the first position the player was taken in the draft, `MinDP`, and the IP was infeasible.

"""

# ╔═╡ a66596b3-f34f-4577-b875-321b70ad1ff1
md"""
## Punting Categories

Care must be taken when building goal programming models to determine the priority of objectives. In our case, all objectives matter equally since that is how the fantasy league scoring works. But what if we decided to give up on a category or two?

It is a common draft strategy to "punt" a category, which is another way of saying that we expect to lose a category for most matchups in an entire season. Taken to an extreme, we might assume a zero for that category and *never* win that category.

A key reason this is done is because certain categories are niche and difficult to predict. A common option is saves and holds, since those depend on a few things:

1. The number of save or hold situations a team has in a year (team skill)
2. The relief pitcher being used in those situations (manager's discretion & player skill)
3. The relief pitcher converting that opportunity (player skill)

As you can see, there is a lot left out of the control of the player's skill. This makes it difficult to project and often means players who are expected to have a lot of saves and holds end up with a lot less, and vice versa. Additionally, only relief pitchers can obtain this statistic, and while they do hold value in other pitching categories, often their counting stats are severely lacking.

Another category that is a candidate to be punted is wins, for many of the same reasons. The stat is difficult to accurately predict, plus we have seen that it is a bottleneck in our model regardless of the projection system used.

Let's rerun our base case for three different scenarios where we punt:
* `SOLD`s
* Wins
* `SOLD`s & Wins

We will adjust our helper function for this scenario as well.
"""

# ╔═╡ eb9d5883-ae90-4e68-8025-2d2a365d452c
begin
	punt_solds = filter(((k,v),) -> k != "SOLD", targets)
	punt_wins = filter(((k,v),) -> k != "W", targets)
	punt_solds_wins = filter(((k,v),) -> k ∉ ["SOLD", "W"], targets)

	punts = OrderedDict("Base" => targets,
						"Punt SOLDs" => punt_solds, 
						"Punt Wins" => punt_wins, 
						"Punt Solds & Wins" => punt_solds_wins)
end	

# ╔═╡ d235c966-786e-45e3-a81a-8b8bcb8362a3
"""
# Punting Categories Scenario

This function iterates through a list of categories to be punted and compares the subsequent model results.

Arguments
- `punts::OrderedDict{String, OrderedDict{String, Real}}`: A dictionary of target dictionaries where certain categories are punted

Returns   

- `roster_df::DataFrame`: DataFrame where each column is the roster in draft order for a scenario
- `stats_df::DataFrame`: DataFrame where each column is the team category totals for a scenario
"""
function run_scenario_analysis(punts::OrderedDict{String, OrderedDict{String, Real}})

	# initialize empty roster df
	roster_df = DataFrame()
	
	# initialize stats df and add targets
	stats_df = DataFrame(Category = [k for k ∈ keys(targets)],
						 Target=[targets[k] for k ∈ keys(targets)])

	# convert ratio targets from sum to avg
	stats_df[5, :Target] = stats_df[5, :Target] / 13
	stats_df[[9, 10], :Target] = stats_df[[9, 10], :Target] / 10


	# loop through scenarios and create new column in all dfs
	for new_targets ∈ keys(punts)
		roster, stats = fantasy_draft(punts[new_targets], position_min; 
		print=false, export_arrays=true)
	
		roster_df[:, new_targets] = roster
		stats_df[:, new_targets] = stats
	end

	return roster_df, stats_df
end

# ╔═╡ d6605196-5a51-4d00-b59f-5f0e497853a4
md"""
By punting `SOLD`s, all relievers on the roster are replaced with additional starters or position players. Two additional position players were swapped in for pitchers, while Camilo Doval and Evan Phillips were replaced with Bobby Miller and Logan Gilbert, respectively. Otherwise, the rosters look remarkably similar.

> **Note:** In my real-life fantasy draft, I took Gilbert and Miller in these exact spots following a similar strategy.

By punting wins, the roster composition is very different, with around half of the slots being new players. Interestingly, the model chooses to take only two starters and fill the rest of the pitching out with a bounty of premium relievers. This could be an effective strategy since relief pitchers generally have better ratios than starting pitchers. Also, it is no mistake that the model took Kevin Gausman and Blake Snell as the only starters; both of those players are strikeout machines which is something that a roster built entirely of relievers would struggle to accumulate.

By choosing to punt `SOLD`s and `W`s, the roster skews towards hitters. The first few pitchers taken are Blake Snell, Dylan Cease, and Nick Pivetta: three players with a very high projected strikeout total. The rest of the pitchers are taken towards the end of the draft, implying that there is a large skills dropoff in terms of strikeouts after Pivetta in round 14.

Now let's see how the team stat totals compare among the different scenarios:
"""

# ╔═╡ 2896b638-5ba7-4788-bc48-5f7573aa7b3d
md"""
Punting `SOLD`s provides a benefit to all offensive categories except `OBP`, with very little decrease in strikeouts. `WHIP` is actually improved here, but `ERA` takes a solid hit. This can be attributed to there being no relievers on the roster, who typically have better `ERA`s than starters.

I am surprised that punting wins did not provide more benefit considering that it seems like earlier analyses seemed to indicate that wins were a binding constraint. There is marginal improvement in most of all offensive stats except `HR`s. The biggest difference is that a team with this roster will be so strong in `SOLD`s that they are almost guaranteed to win it most weeks. The pitching ratios are also strengths, as `ERA` is reduced drastically. Now it looks like strikeouts is almost a binding constraint, which makes sense given the two starting pitchers it chose.

By punting `SOLD`s and wins, all hitting categories receive a massive boost, at the expense of pitching. With the exception of maybe strikeouts, this strategy is essentially punting *all* pitching. By taking starters that excel in generating strikeouts only, `ERA` and `WHIP` are too high to be competitive on a weekly basis. Again, given the roster construction this is not a surpise.

Based on the above, it seems like punting `SOLD`s is the only viable strategy if you want to remain competitive in the remaining stats.
"""

# ╔═╡ b7deb98a-d2cc-49cc-9598-3b3c29d51301
md"""
## Starting Draft Position

Conventional wisdom would suggest that having the first selection in a fantasy draft would result in the best (theoretical) team among others in the league. This is usually because there is a sharp skills dropoff after the first few picks. There is a tradeoff though: the snake format of the draft means that the person with the first overall selection will then have the *last* pick in the second round. In the case of a 12-team league, this means they will have picks 1 and 24. Conversely, the person with the last pick in the first round will have the *first* pick of the second round. In a 12-team league, this means they would own picks 12 and 13. The question is: which position is more optimal?

The base model assumes a 12-team league and that the model is drafting in the last spot of the first round. This is because this is where I drafted earlier this season. We will rerun the base case assuming I instead had the first and sixth pick to see how this affects the final roster and the overall stat totals.

Let's start by editing the scenario helper function.
"""

# ╔═╡ 7b63073d-8f7b-48d5-bd31-95b59e74ca55
starting_positions = [1, 6, 12]

# ╔═╡ b7c7d0d2-397e-4350-b57a-71abd8b11cc9
"""
# Starting Draft Position Scenario

This function iterates through a list of starting draft positions in round 1 and compares the subsequent model results.

Arguments
- `targets::OrderedDict{String, Real}`: A dictionary of the categories and their corresponding target
- `starting_positions::Array{Int64, 1}`: List of starting draft positions in the first round

Returns   

- `roster_df::DataFrame`: DataFrame where each column is the roster in draft order for a scenario
- `stats_df::DataFrame`: DataFrame where each column is the team category totals for a scenario
"""
function run_scenario_analysis(targets::OrderedDict{String, Real},
							   starting_positions::Array{Int64, 1})

	# initialize empty roster df
	roster_df = DataFrame()
	
	# initialize stats df and add targets
	stats_df = DataFrame(Category = [k for k ∈ keys(targets)],
						 Target=[targets[k] for k ∈ keys(targets)])

	# convert ratio targets from sum to avg
	stats_df[5, :Target] = stats_df[5, :Target] / 13
	stats_df[[9, 10], :Target] = stats_df[[9, 10], :Target] / 10


	# loop through scenarios and create new column in all dfs
	for num ∈ starting_positions
		roster, stats = fantasy_draft(targets, position_min; 
		start_position=num, print=false, export_arrays=true)
	
		roster_df[:, "Pick $num"] = roster
		stats_df[:, "Pick $num"] = stats
	end

	return roster_df, stats_df
end

# ╔═╡ 65c53df3-2b0e-4630-ba90-361482436101
md"""
In very rare cases, there is a consensus #1 pick. Coming into the 2024 season, Ronald Acuna Jr. was that player. It comes as no surpise that the *Pick 1* model selects him first overall. He is coming off a a 50 home run, 70 stolen base season! Just his contribution to the team totals will be a massive. Beyond drafting a hitter in the first round, the *Pick 1* model only slightly deviates from the strategy followed by the *Pick 12* model (the base case). Both models target starting pitching and then relief pitching in the first several rounds, and many of the same players make up both teams. Again, this tells me that these players are great values and should be targeted in my real life draft. There are several new players that essentially fill similar functions: Andres Munoz replaces Camilo Doval, Max Fried replaces Zack Wheeler, and Shea Langaliers replaces Logan O'Hoppe.

Looking at the *Pick 6* model, it again opts for a power-speed bat in Fernando Tatis Jr., a player with a similar ceiling to Acuna, but a lower floor. Actually, it makes more sense to compare this one to the *Pick 1* model since there are only **three** players on both rosters that differ. Three! This deserves taking a deeper dive into the differences (or similarities) among these players. 

Starting with Tatis, as stated above, we should compare him directly to Acuna. Tatis is projected for 20 less steals, 20 less runs, and nearly 50 points less in `OBP`. Home runs and RBIs are projected to be nearly the same for both players. This suggests that the difference in these categories will need to be recouped with the other two players. Looking at the catcher slot, the *Pick 6* model opts for Henry Davis over Shea Langaliers. Davis offers 6 more stolen bases, 8 more runs, and over 60 points of `OBP`. The tracks with our hypothesis so far. The last player swap that the *Pick 6* model makes is Ryan McMahon for Jack Suwinski. McMahon provides 7 more runs but 2 less stolen bases, with a slightly better `OBP` than Suwinski. To account for the Acuna effect, the *Pick 6* model selects Davis and McMahon to close the gap in runs by 15 and making up for `OBP` almost entirely. It does not seem like it can entirely make up for the stolen bases Acuna is projected for, leaving a gap of 16 between the two models.

We can look at this more closely by examining the team category totals for each scenario.
"""

# ╔═╡ da975966-af09-42fe-82b1-b147c9d2a0b0
md"""
My reasoning for selecting pick 12 in my real-life draft was that I would rather have two fringe first rounders than have the first overall selection and then have to wait until almost round 3 to have my second pick. It was a decision very much based on intuition, and this data does not necessarily support or reject it. 

There are 55 more steals and 35 more runs projected if I would have chose the first pick, but otherwise? Very similar. In fact, the *Pick 12* model has over 50 more strikeouts and 12 more `SOLD`s. This feels like a wash.

As we might have guessed, the *Pick 1* and the *Pick 6* model have almost the same projected end of season statistics. The only glaring exception is steals, which is 16 stolen bases lower because it does not have Acuna. 

Overall, it is not clear what the best strategy is based off of starting draft position. Besides having Acuna, the rosters are built very similarly and have more or less the same projected stats. The snake-like nature of the draft is meant to level the playing field amongst all teams, and despite my prediction, it appears to do a reasonably good job at it.
"""

# ╔═╡ 456630b8-594d-40b4-b1c9-54cfe459fb0e
md"""
## Relax Goal Bounds

For our final scenario analysis, we will remove the requirement that each target must be met. This should allow certain categories to greatly exceed what is needed to win the fantasy league at the expense of others. Overall, it should be a very unbalanced team.
"""

# ╔═╡ 01c05948-6397-4565-b714-69193c0ac5bb
goal_bounds = OrderedDict("Strict" => true, "Relaxed" => false)

# ╔═╡ 50857ee7-3c50-46e7-83ff-3cf985c0a505
"""
# Goal Bounds Scenario

This function iterates through strict and relaxed scenarios for goal bounds and compares the model results.

Arguments
- `targets::OrderedDict{String, Real}`: A dictionary of the categories and their corresponding target
- `goal_bounds::OrderedDict{String, Bool}`: A dictionary for strict and relaxed goal bounds

Returns   

- `roster_df::DataFrame`: DataFrame where each column is the roster in draft order for a scenario
- `stats_df::DataFrame`: DataFrame where each column is the team category totals for a scenario
"""
function run_scenario_analysis(targets::OrderedDict{String, Real},
							   starting_positions::OrderedDict{String, Bool})

	# initialize empty roster df
	roster_df = DataFrame()
	
	# initialize stats df and add targets
	stats_df = DataFrame(Category = [k for k ∈ keys(targets)],
						 Target=[targets[k] for k ∈ keys(targets)])

	# convert ratio targets from sum to avg
	stats_df[5, :Target] = stats_df[5, :Target] / 13
	stats_df[[9, 10], :Target] = stats_df[[9, 10], :Target] / 10


	# loop through scenarios and create new column in all dfs
	for bound ∈ keys(goal_bounds)
		roster, stats = fantasy_draft(targets, position_min, goal_bounds[bound]; 
		print=false, export_arrays=true)
	
		roster_df[:, bound] = roster
		stats_df[:, bound] = stats
	end

	return roster_df, stats_df	
end

# ╔═╡ 9e0ef014-53c4-45f3-ac02-afc0cc3bb269
roster_proj, stats_proj, positions_proj = run_scenario_analysis(targets,
										  position_min, projections)

# ╔═╡ 53ab34aa-6fa9-4a76-a5c9-85d50be9b7ce
roster_proj

# ╔═╡ 13b9cec6-0364-4de7-970e-3b90e5783437
stats_proj

# ╔═╡ a2abbd75-1cb8-4f7b-8e4b-cb9d1cc53f08
positions_proj

# ╔═╡ 2b00da3f-f7d5-4e16-9b6f-d4d552d6c01a
roster_dv, stats_dv = run_scenario_analysis(targets, draft_values)

# ╔═╡ 24a737a7-9f4d-4cef-8807-8009c37d175f
roster_dv

# ╔═╡ 3abfc95d-b0bd-45a9-b417-97702432f128
stats_dv

# ╔═╡ 9af12396-88c6-4bb3-8367-1bfa31e8fefa
roster_punt, stats_punt = run_scenario_analysis(punts)

# ╔═╡ 06c5ec40-d6bd-474a-bd4e-b0decc07e11a
roster_punt

# ╔═╡ f0e2fa8f-de72-4170-b65b-a1ce02c38051
stats_punt

# ╔═╡ 1994cbca-44bd-484b-bf89-0a8b0dcac797
roster_pick, stats_pick = run_scenario_analysis(targets, starting_positions)

# ╔═╡ d744dd56-31fa-4469-8804-d73ae9e03f01
roster_pick

# ╔═╡ 210e96bc-b716-4c74-880c-88839a47eccb
stats_pick

# ╔═╡ 09c5858d-cf44-44b1-a3fe-741297ece7e0
roster_bounds, stats_bounds = run_scenario_analysis(targets, goal_bounds)

# ╔═╡ ba991ed7-59f8-48d7-8c76-0e48d1ec9489
roster_bounds

# ╔═╡ 6e53fa35-0d5e-42cd-919e-03d6a894dd66
md"""
The strategy that the model chooses is very interesting: do not draft any starting pitchers. This is not surpising given the fact that wins are difficult to come by, as we have not seen *any* permutation of this model have a win total above the 100 win threshold. 

The *Relaxed* model opts to take two premium bats in the first couple rounds: Aaron Judge and Jose Ramirez. Both are balanced hitters that have a good amount of pop. Ramirez projects for about 30 steals as well. Since starters are not valued here,  the model takes two of the best relievers in the whole draft: Edwin Diaz and Josh Hader. These guys have big strikeout upside and a proven track record of success. The second half of the draft looks remarkably similar to the *Strict* model though.

Let's take a look at how this impacts our objectives:
"""

# ╔═╡ fbe92cf9-5233-4fee-9f4d-769a9476289f
stats_bounds

# ╔═╡ fd56a380-dfa7-4eab-a6cb-c8438eb2bdf9
md"""
All offensive categories are supercharged, which is heavily driven by Judge and Ramirez. As expected, not drafting any starters is tentamount to punting wins and strikeouts most weeks. Both categories are high enough that it is possible to steal those two categories in some weeks. By having a pitching staff built entirely of relievers, the pitching ratios are elite, so this should be a strong advantage as well.

The *Relaxed* model is less balanced, but not to the extreme that I anticipated. The roster is very strong in eight categories, which most weeks should be enough to win the matchup. I do think this fantasy team could make the playoffs, the question becomes how deep they could go. You are essentially giving the other team two points, so you would really need to have the advantage in all others to have a chance.

As an aside, I do wonder what effect drafting the *Relaxed* model's roster would have on the league as a whole. You would essentially be hording all of the top-end relief pitchers, which would leave others with little alternatives. In the real world, other teams would be forced to adjust their draft strategy live to deal with the substantial changes you are making. Put another way, it is unlikely you would actually be able to draft all of these relievers. Generally, when one reliever goes early, it prompts someone soon after to select a relief pitcher as well. This can snowball into a run on relief pitchers due to the perception that they might be gone sooner than normal. By the time it is your turn to make another pick, some of the guys you wanted might not be there anymore.

> **Note:** In my real draft, I actually selected several players that showed up in the *Relaxed* model: Jose Ramirez, Edwin Diaz, Cedric Mullins, and Daulton Varsho. My strategy was actually to soft punt saves and holds. My reasoning was that a lot of `SOLD`s are actually earned from waiver wire pickups anyway, so why waste premium draft capital on them?
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
OrderedCollections = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"

[compat]
CSV = "~0.10.13"
DataFrames = "~1.6.1"
HiGHS = "~1.9.0"
JuMP = "~1.20.0"
OrderedCollections = "~1.6.3"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.10.2"
manifest_format = "2.0"
project_hash = "535dae47a48bdbb9f0665d1616556bc96ebb92d8"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "f1dff6729bc61f4d49e140da1af55dcd1ac97b2f"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.5.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9e2a6b69137e6969bab0152632dcb3bc108c8bdd"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+1"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "PrecompileTools", "SentinelArrays", "Tables", "Unicode", "WeakRefStrings", "WorkerUtilities"]
git-tree-sha1 = "a44910ceb69b0d44fe262dd451ab11ead3ed0be8"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.13"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "9b1ca1aa6ce3f71b3d1840c538a8210a043625eb"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.8.2"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "59939d8a997469ee05c4b4944560a820f9ba0d73"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.4"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "c955881e3c981181362ae4088b35995446298b80"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.14.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.1.0+0"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "abe83f3a2f1b857aac70ef8b269080af17764bbe"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.16.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "DataStructures", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrecompileTools", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SentinelArrays", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "04c738083f29f86e62c8afc341f0967d8717bdb8"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.6.1"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "0f4b5d62a88d8f59003e43c25a8a90de9eb76317"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.18"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "23163d55f885173722d1e4cf0f6110cdbaf7e272"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.15.1"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "9f00e42f8d99fdde64d40c8ea5d14269a2e2c1aa"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.21"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "cf0fe81336da9fb90944683b8c41984b08793dad"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.36"

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

    [deps.ForwardDiff.weakdeps]
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.HiGHS]]
deps = ["HiGHS_jll", "MathOptInterface", "PrecompileTools", "SparseArrays"]
git-tree-sha1 = "a216e32299172b83abfe699604584f413ffbb045"
uuid = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
version = "1.9.0"

[[deps.HiGHS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "9a550d55c49334beb538c5ad9504f07fc29a13dc"
uuid = "8fd58aa0-07eb-5a78-9b36-339c94fd15ea"
version = "1.7.0+0"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InvertedIndices]]
git-tree-sha1 = "0dc7b50b8d436461be01300fd8cd45aa0274b038"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.3.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7e5d6779a1e09a36db2a7b6cff50942a0a7d0fca"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.5.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MacroTools", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays"]
git-tree-sha1 = "4e44cff1595c6c02cdbca4e87ce376e63c33a584"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.20.0"

    [deps.JuMP.extensions]
    JuMPDimensionalDataExt = "DimensionalData"

    [deps.JuMP.weakdeps]
    DimensionalData = "0703355e-b756-11e9-17c0-8b28908087d0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "50901ebc375ed41dbf8058da26f9de442febbbec"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.4.0+0"

[[deps.LibGit2]]
deps = ["Base64", "LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.6.4+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "18144f3e9cbe9b15b070288eef858f71b291ce37"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.27"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "2fa9ee3e63fd3a4f7a9a4f4744a52f4856de82df"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.13"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays", "SpecialFunctions", "Test", "Unicode"]
git-tree-sha1 = "d268e82322cc5df142a3664d03d59adecd53abf9"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.27.1"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2023.1.10"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "2d106538aebe1c165e16d277914e10c550e9d9b7"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.4.2"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.23+4"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+2"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "dfdf5519f235516220579f949664f1bf44e741c5"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.6.3"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.1"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.10.0"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "36d8b4b899628fb92c2749eb488d884a926614d3"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.3"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "5aa36f7049a63a1528fe8f7c3f2113413ffd4e1f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.1"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "9306f6085165d270f7e3db02af26a400d580f5c6"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.3"

[[deps.PrettyTables]]
deps = ["Crayons", "LaTeXStrings", "Markdown", "PrecompileTools", "Printf", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "88b895d13d53b5577fd53379d913b9ab9ac82660"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.3.1"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "0e7508ff27ba32f26cd459474ca2ede1bc10991f"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.4.1"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "66e0a8e672a0bdfca2c3f5937efb8538b9ddc085"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.1"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.10.0"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "e2cfc4012a19088254b3950b85c3c1d8882d864d"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.3.1"

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

    [deps.SpecialFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"

[[deps.StaticArraysCore]]
git-tree-sha1 = "36b3d696ce6366023a0ea192b4cd442268995a0d"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.2"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.10.0"

[[deps.StringManipulation]]
deps = ["PrecompileTools"]
git-tree-sha1 = "a04cabe79c5f01f4d723cc6704070ada0b9d46d5"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.4"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.2.1+1"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits"]
git-tree-sha1 = "cb76cf677714c095e535e3501ac7954732aeea2d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.11.1"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
git-tree-sha1 = "14389d51751169994b2e1317d5c72f7dc4f21045"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.10.6"
weakdeps = ["Random", "Test"]

    [deps.TranscodingStreams.extensions]
    TestExt = ["Test", "Random"]

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[deps.WorkerUtilities]]
git-tree-sha1 = "cd1659ba0d57b71a464a29e64dbc67cfe83d54e7"
uuid = "76eceee3-57b5-4d4a-8e66-0e911cebbf60"
version = "1.6.1"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+1"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.8.0+1"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.52.0+1"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+2"
"""

# ╔═╡ Cell order:
# ╟─a7af3923-1317-49f9-bbc2-dc8f3b735aa5
# ╟─4c6fe46b-1c25-4f9a-bd88-63ffb7e84a39
# ╟─adf90438-b24e-4e80-8ceb-b47ca2f3a67d
# ╠═7d4d5798-fac3-11ee-0020-a3bc46fa36d2
# ╟─a124c6c7-dcc2-4243-bf38-a4229b902be4
# ╠═b91d11e0-dcf4-4e17-bd85-1e4de7e91278
# ╟─8b8911bd-8048-499b-915b-43f820ccf29c
# ╠═e2439dac-168d-4e99-a1f7-e377e71ed104
# ╠═ca2c2ce7-3ee3-4c0d-8852-7d8d24757906
# ╠═08151864-5f70-4870-8e7a-ad51490b70b4
# ╠═51046ed3-195d-4e2d-be12-96e2348ac7fe
# ╠═789e86f3-c4ca-4a0c-9974-5079468881c1
# ╟─b08ca88d-9e21-46d4-8d1f-fc16df6905e3
# ╠═e847c6fb-2df7-4e46-bcdd-0352babf7826
# ╟─d7da5063-6824-4b79-a3af-3d25dfe5f4ea
# ╟─5b71337e-2b99-4d37-9499-896f079e60ae
# ╠═ef26e745-741f-4d93-a5df-e9cf84966cfb
# ╠═0a8f41f7-c29f-46ce-bce5-93a5b0d6115b
# ╠═9e0ef014-53c4-45f3-ac02-afc0cc3bb269
# ╠═53ab34aa-6fa9-4a76-a5c9-85d50be9b7ce
# ╟─095f7ad1-8e74-4f2c-954a-7db24133680a
# ╠═13b9cec6-0364-4de7-970e-3b90e5783437
# ╟─4e9f2530-7055-4ba2-a8a8-81497f3e5efe
# ╠═a2abbd75-1cb8-4f7b-8e4b-cb9d1cc53f08
# ╟─ef7b348e-f4d9-4296-a877-a6e55dbd7faa
# ╟─97ce6cd2-4763-4d0f-99bd-15ad38995c31
# ╠═b77c387d-872a-466c-a8c6-427f76494349
# ╠═ce5a4b0a-7bca-48ec-9c02-2e29bd83fd6c
# ╠═2b00da3f-f7d5-4e16-9b6f-d4d552d6c01a
# ╠═24a737a7-9f4d-4cef-8807-8009c37d175f
# ╟─e3202458-11ae-40a0-90ce-21d1720b536d
# ╠═3abfc95d-b0bd-45a9-b417-97702432f128
# ╟─107f7761-75f5-4928-b47a-051e82a45e1d
# ╟─a66596b3-f34f-4577-b875-321b70ad1ff1
# ╠═eb9d5883-ae90-4e68-8025-2d2a365d452c
# ╠═d235c966-786e-45e3-a81a-8b8bcb8362a3
# ╠═9af12396-88c6-4bb3-8367-1bfa31e8fefa
# ╠═06c5ec40-d6bd-474a-bd4e-b0decc07e11a
# ╟─d6605196-5a51-4d00-b59f-5f0e497853a4
# ╠═f0e2fa8f-de72-4170-b65b-a1ce02c38051
# ╟─2896b638-5ba7-4788-bc48-5f7573aa7b3d
# ╟─b7deb98a-d2cc-49cc-9598-3b3c29d51301
# ╠═7b63073d-8f7b-48d5-bd31-95b59e74ca55
# ╠═b7c7d0d2-397e-4350-b57a-71abd8b11cc9
# ╠═1994cbca-44bd-484b-bf89-0a8b0dcac797
# ╠═d744dd56-31fa-4469-8804-d73ae9e03f01
# ╟─65c53df3-2b0e-4630-ba90-361482436101
# ╠═210e96bc-b716-4c74-880c-88839a47eccb
# ╟─da975966-af09-42fe-82b1-b147c9d2a0b0
# ╟─456630b8-594d-40b4-b1c9-54cfe459fb0e
# ╠═01c05948-6397-4565-b714-69193c0ac5bb
# ╠═50857ee7-3c50-46e7-83ff-3cf985c0a505
# ╠═09c5858d-cf44-44b1-a3fe-741297ece7e0
# ╠═ba991ed7-59f8-48d7-8c76-0e48d1ec9489
# ╟─6e53fa35-0d5e-42cd-919e-03d6a894dd66
# ╠═fbe92cf9-5233-4fee-9f4d-769a9476289f
# ╟─fd56a380-dfa7-4eab-a6cb-c8438eb2bdf9
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
