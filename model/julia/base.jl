### A Pluto.jl notebook ###
# v0.19.40

using Markdown
using InteractiveUtils

# ╔═╡ 05c61bd0-e94b-11ee-0448-ab92a4e36eb7
using JuMP, HiGHS, CSV, DataFrames, OrderedCollections

# ╔═╡ 34aabfbf-46a7-48ed-8696-baab5a06d5b5
md"""
# Fantasy Baseball Draft - Base Case
**Jacob Norman**

* Scenario: Base
* Hitters: *THE BAT X*
* Pitchers: *ATC*
"""

# ╔═╡ 73b5ff4b-f74b-442f-9679-f7023f5bc4a2
md"""
## Introduction

This document is a walkthrough of a fantasy baseball draft optimization model. This is the final project for my ISE501 course. Coincidentally, when I began this project I had a fantasy baseball draft that was coming up, so the intention was for this analysis to inform my actual draft strategy.

Here are a few notes about the fantasy league:
* 12 teams
* 25 rounds in draft
"""

# ╔═╡ 89176410-3afb-49ca-b296-a5e510f147d2
md"""
## Preprocessing

Before we actually start to build the model, let's read in the data that this will be based on. The projections are courtesy of [Fangraphs](https://www.fangraphs.com). The hitters are using *THE BAT X* projections, while pitchers projections are based off *ATC*. 

I chose *THE BAT X* as my favored source of projections because they are leveraging Statcast data. These are process-oriented metrics that include, but are not limited to: average launch angle, average exit velocity, and hard hit rate. In other words, these capture the hitter's underlying approach to predict their future statistics, not just their past outcomes alone.

Normally, I would like the projections of both the hitters and the pitchers to be from the same source; however, *THE BAT X* only projects for hitters at present, so I opted to use the *ATC* projections for pitchers. *ATC* stands for **A**verage **T**otal **C**ost and, as its name suggests, it averages the projections of several different sources.

**A**verage **D**raft **P**osition (`ADP`) and related information is sourced from [NFBC](https://nfc.shgn.com/baseball) Rotowire Online 12-team leagues for the month of March. In fact, I only pulled the players into the model if they were drafted during this time period.

First, let's load the required packages:
"""

# ╔═╡ 46e54092-e74c-4d2c-853a-59a0489667ba
md"""
The `HiGHS.jl` library is an open-source solver that is great for mixed-integer LPs. This is exactly what I need, because I first wrote this model in GAMS, but ran into trouble with the limit on decision variables that came with the academic license.


Next, we will read in the DataFrame:
"""

# ╔═╡ 068cb0f0-1c0f-421d-8d56-5707be32e9dc
df = DataFrame(CSV.File("../../data/batx_atc.csv"))

# ╔═╡ 0712c423-262c-46e7-b996-2be27e79d669
md"""
The format of the fantasy baseball league is 5x5 roto, which means that we track five different statistical categories each for hitters and pitchers.

For hitters:
* **H**ome **R**uns (`HR`)
* **R**uns scored (`R`)
* **R**uns **B**atted **I**n (`RBI`)
* **S**tolen **B**ases (`SB`)
* **O**n **B**ase **P**ercentage (`OBP`)

For pitchers:
* **W**ins (`W`)
* **S**trike**O**uts (`SO`)
* **S**aves plus H**OLD**s (`SOLD`)
* **E**arned **R**un **A**verage (`ERA`)
* **W**alks + **H**its / **I**nnings **P**itched (`WHIP`)

Right now, we do not have a field for `SOLD`s, but we do have `SV` and `HLD`, so we will make that now:
"""

# ╔═╡ 01875dcf-f38a-407c-8691-f08952e29283
df[:, :SOLD] = df[:, :SV] .+ df[:, :HLD]

# ╔═╡ 8930bbad-ff16-464b-9236-4dd8ac78d500
md"""
## Model

We will format the model similar to a GAMS file since I am porting this over from there. Firstly, let's initialize the model.

"""

# ╔═╡ 1ebf6238-68e0-4965-8f52-94dcf724c88a
model = Model(HiGHS.Optimizer)

# ╔═╡ 609ad202-fb66-45d4-a308-56acef5e4270
md"""
## Sets

The two primary sets are as follows:
* `i` --> player name (team)
* `j` --> round in draft
"""

# ╔═╡ d5dc21ba-f8f7-490f-91fa-fc549d2f9aec
begin
	n = length(df[:, :player])
	m = 25
end

# ╔═╡ efdfd4d2-596c-44d9-978b-4d2e541d35b5
md"""
I had to include the team the player currently belongs to as part of the player ID, since there are two players that had the same first and last names, Will Smith and Logan Allen. 

With that in mind, there are $n unique players and $m rounds in the draft. For mathematical formulations, we will just use the player's index out of $n. This means that we will have $(n * m) decision variables!
"""

# ╔═╡ 334c0497-e812-43ac-bbcc-63c3fa5c3b87
md"""
## Parameters

Let's define parameters that will be used in the model, starting with some league information.
"""

# ╔═╡ ea49bdfa-a22b-4156-a664-ed7dc2a3f5f4
begin
	teams = 12 			 # number of teams in fantasy league
	start_position = 12  # starting draft position in round one
end

# ╔═╡ e5ebadec-b2f2-4fa5-8666-d56e8346bb39
md"""
Next, we will establish the targets for each of the 10 categories. These are based on the winning team's numbers from last year's fantasy league. I did not look back any further due to significant rule changes in the MLB that began in the 2023 season. With the exception of `ERA` and `WHIP`, the goal is the exceed all of these targets.
"""

# ╔═╡ f991061a-2be5-4563-93f8-2f1f7730fee1
targets = OrderedDict("HR" => 275, 
			   		  "R" => 1000, 
			   		  "RBI" => 1000, 
			   		  "SB" => 200, 
			   		  "OBP" => 0.35 * 13,  # assuming 13 hitters
			          "W" => 100, 
				      "SOLD" => 75,
			          "SO" => 1200,
		              "WHIP" => 1.2 * 10,  # assuming 10 pitchers
			          "ERA" => 3.7 * 10)

# ╔═╡ 96b7d9be-0013-4f9d-a300-6e319789f7fe
md"""
> **Important Note:** While most of the categories are counting stats (can only take integer values), there are three measures that are ratios: `OBP`, `WHIP`, and `ERA`. To keep the model linear, I needed to maximize the sum and not the average as I would have liked. To accomplish this, I needed to approximate a target ratio for each stat, which meant I needed to guess the number of hitters and pitchers that will be on my final model roster. This is not a perfect solution, but it will keep everything linear.
"""

# ╔═╡ e243dd01-d94f-48ab-bf5a-a9077e62c2ba
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

# ╔═╡ 24324454-e644-4a56-bdc1-2f8e64e8d03e
md"""
There are also roster considerations; I can't have a team composed entirely of one position. Since there are 25 rounds, I need 25 players on the roster; but only 18 of them can start at any one time (the remaining 7 players are on the bench, although this does not mean they never contribute). The numbers below are the minimum number of each position I need on my team.
"""

# ╔═╡ dcf57186-b704-4a91-97d9-3a8b9d63711a
position_min = OrderedDict("C" => 1, 
						   "1B" => 1, 
						   "2B" => 1, 
						   "3B" => 1, 
						   "SS" => 1, 
						   "INF" => 1 + 4,  # added 4 for other INF reqs
						   "OF" => 4, 
						   "UT" => 1 + 10,  # added 10 for position player reqs
						   "P" => 7)

# ╔═╡ 29e9d160-8ace-48ba-b314-1a4a6dd188ea
md"""
## Decision Variables

The decision the model needs to make is pretty simple: what player should I select in each round of the draft? In practice, this is a single variable with two indexes, `i` and `j`.

> **Important Note:** The decision variable is binary!

$x_{ij} \in \{0, 1\}, for\ i=1-579,\ j=1-25$
"""

# ╔═╡ 4f6ceaac-e93e-480d-a37e-595e53f6cf83
@variable(model,
		  x[df[:, :player], 1:m], 
		  Bin)

# ╔═╡ 78530e8d-e32d-4154-b913-c9a8745e05ec
md"""
# Expressions

We need to build some expressions that relate to the objective function. There will be one term for each statistical category of the following form:

$\frac{\sum_{i=1}^{579}\sum_{j=1}^{25}{proj_{ik}x_{ij}} - target_{k}}
{target_{k}} = obj_{k},$
$for\ k=HR,\ R,\ RBI,\ SB,\ OBP,\ W,\ SOLD,\ SO,\ WHIP,\ ERA$

The subobjectives are formulated this way to normalize the scale of each statistical category; some are in the thousands while others can be less than 10.
"""

# ╔═╡ 6e00d682-8c4e-4250-a6e5-d4383e7caae6
@expression(model,
			obj[k ∈ keys(targets)], 
			((sum(x[df[i, :player], j] * df[i, k] for i=1:n, j=1:m) - targets[k]) / targets[k]))

# ╔═╡ e2b12d7d-df7e-4d9e-b095-705d486e5388
md"""
## Objective Function

With the above expression created, the objective function is fairly straightword:

$max \ z = \sum_{k}{w_{k} obj_{k}}$

We defined the weights earlier, which are simply +1 for categories we seek to maximize and -1 for those we would like to minimize.
"""

# ╔═╡ 258ffcba-e4f2-483f-8173-53e3051af4cd
@objective(model, Max, sum(weights[k] * obj[k] for k ∈ keys(targets)))

# ╔═╡ 890d0a70-c6d8-41d2-95c8-dd2ee0d8b78f
md"""
## Constraints

When written in algebraic form, the model only has a few constraints:
* *RoundMax*
* *PlayerMax*
* *ADPOddMax*
* *ADPEvenMax*
* *PositionMin*

Let's start with the *RoundMax* constraint. This ensures that exactly one player is selected in each round:

$\sum_{i=1}^{579}{x_{ij}} = 1,\ for\ j=1-25$
"""

# ╔═╡ e2911ffd-d89b-4004-8749-b42d116ac841
# RoundMax
@constraint(model, 
			round_max[j ∈ 1:m], 
			sum(x[:, j]) == 1)

# ╔═╡ 7cfdd204-5a2b-40fb-9381-d6b600edfe9e
md"""
Next, we will look at *PlayerMax*, which will make sure that a player is selected at most once in the entire draft. Otherwise, the model could just key on a statistical powerhouse like Ronald Acuna Jr. several times.

$\sum_{j=1}^{25}{x_{ij}} ≤ 1,\ for\ i=1-579$
"""

# ╔═╡ 1c11428a-748b-4438-8dca-0e6f684343ad
# PlayerMax
@constraint(model, 
			player_max[i ∈ df[:, :player]], 
			sum(x[i, :]) <= 1)

# ╔═╡ 255d8fd3-15a5-47d7-96d0-203cb0f4fc30
md"""
One challenge with this model is that we are attempting to apply deterministic methods to something that is inherently stochastic; we cannot know what players will be available during each round in the draft with certainty.

To account for this, the *ADPOddMax* and *ADPEvenMax* constraints will ensure that no player is selected before their `ADP`. This is essentially a best guess as to when the player will be selected.

Since this is a snake draft, there are two different patterns. For odd rounds:

$\sum_{i=1}^{579}{ADP_{i}x_{ij}} ≥ teams(j-1) + start\_position,\ for\ j=1,3,5,...,25$
"""

# ╔═╡ f2e2cd8e-59c8-452d-bf12-0e6181e6c2c5
# ADPOddMax
@constraint(model, 
			adp_odd_max[j ∈ 1:2:m], 
			sum(df[i, :ADP] * x[df[i, :player], j] 
			for i=1:n) >= teams * (j - 1) + start_position)

# ╔═╡ 4b00b875-9516-46de-8d2e-22bc8733334d
md"""
For even rounds in the draft:

$\sum_{i=1}^{579}{ADP_{i}x_{ij}} ≥ teams(j-2) + start\_position + 1,\ for\ j=2,4,6,...,24$
"""

# ╔═╡ 3b3ef5fa-b3e8-4710-9fed-c60aa991f98a
# ADPEvenMax
@constraint(model, 
			adp_even_max[j ∈ 2:2:m], 
			sum(df[i, :ADP] * x[df[i, :player], j]
			for i=1:n) >= teams * (j - 2) + start_position + 1)

# ╔═╡ 952b73e1-d052-4188-afd4-896bb754ec4c
md"""
A key part of team construction is making sure you have a sufficient number of players eligible to play all positions. The constraint *PositionMin* accomplishes this:

$\sum_{i=1}^{579}\sum_{j=1}^{25}{Pos_{ip}x_{ij}} ≥ MinPos_{p},\ for\ p=C,\ 1B,\ 2B,\ 3B,\ SS,\ INF,\ OF,\ UT,\ P$
"""

# ╔═╡ c0b8e207-3b0d-4265-93b4-dbc607ad9f9b
# PositionMin
@constraint(model, 
			pos_m[p ∈ keys(position_min)], 
			sum(df[i, p] * x[df[i, :player], j] 
			for i=1:n, j=1:m) >= position_min[p])

# ╔═╡ f189408f-5231-47e5-9746-5b2cb3ad0e50
md"""
Lastly, we need to add non-negativity constraints for the categories we want to maximize and non-positivity constraints for those we want to minimize. The bounds of $x_{ij}$ are already accounted for since we defined it as a binary variable, but we need to still do this for $obj_{k}$.

We *could* keep these values as free variables, but I would like to at least hit the target on all of the categories. The reason being the outcome of each category is win, lose, or tie; there are no additional points for winning by a large margin. Otherwise, other categories could be compromised.

As a reminder, we would like `WHIP` and `ERA` to be as small as possible, and would like to maximize all other stats.
"""

# ╔═╡ 6e59a964-ea5c-4159-b4d2-99d514ab033f
begin
	positive_categories = ["HR", "R", "RBI", "SB", "OBP", "W", "SOLD", "SO"]
	negative_categories = ["WHIP", "ERA"]
end

# ╔═╡ 0560224e-d385-430c-807e-4131b91fcd1c
md"""
$obj_{k} ≥ 0,\ for\ k=HR,\ R,\ RBI,\ SB,\ OBP,\ W,\ SOLD,\ SO$
"""

# ╔═╡ 1d96d749-ff96-49aa-89af-372ff61d1504
@constraint(model,
			positive_goal[k in positive_categories],
			obj[k] >= 0)

# ╔═╡ b59b5fe4-6bb5-4549-aaad-494594c915de
md"""
$obj_{k} ≤ 0,\ for\ k=WHIP,\ ERA$
"""

# ╔═╡ 290baa5c-8975-4db5-9d9f-9b5927cc42f7
@constraint(model,
			negative_goal[k in negative_categories],
			obj[k] <= 0)

# ╔═╡ e0f87ac8-3bb4-4bd8-94da-42ec587622ba
md"""
## Solution

With all of that formulated, we can solve the model:
"""

# ╔═╡ 5e97a550-6461-4a02-ab72-16847ca20182
# ╠═╡ skip_as_script = true
#=╠═╡
begin
	optimize!(model)
	#solution_summary(model)
end
  ╠═╡ =#

# ╔═╡ 82af4416-ce57-4ac5-af25-d684de12085f
md"""
The solver found a solution, so let's see what team it drafted for us:
"""

# ╔═╡ 8ee31704-9e55-4f6a-bafe-8eda6259c7ab
begin
	# initialized all players with 0
	drafted_players = OrderedDict(i => 0 for i ∈ df[:, :player])

	# assign round to players that were drafted
	for j in 1:m, i ∈ df[:, :player]
	    if round(value(x[i, j])) == 1
			drafted_players[i] = j
		end
	end

	# add to df
	df[:, :round] = [drafted_players[i] for i ∈ df[:, :player]]

	# create new df
	drafted_players_df = filter(:round => >=(1), df)
	sort!(drafted_players_df, order(:round))

	# display roster
	show(select(drafted_players_df, :player), allrows=true)
end

# ╔═╡ 12d1a9fa-43bf-4377-8629-65491080695d
md"""
The model went very heavy on the pitching early in the draft and made up for the lack of bats later on. This is actually the opposite of most modern draft strategies that tend to prioritize hitters in the first few rounds.

Let's see how our projected stat totals ended up:
"""

# ╔═╡ 9149e595-0f96-4240-98bc-b42fdf45a8ed
begin
	# create stats df
	stats = DataFrame((
				category = [k for k ∈ keys(targets)],
				target = [targets[k] for k ∈ keys(targets)],
				actual = [sum(drafted_players_df[:, k]) for k ∈ keys(targets)]
		   ))
	
	# adjust target ratios to average
	stats[5, :target] = stats[5, :target] / 13
	stats[[9, 10], :target] = stats[[9, 10], :target] / 10

	total_hitters = sum(drafted_players_df[:, :UT])
	total_pitchers = sum(drafted_players_df[:, :P])
	stats[5, :actual] = stats[5, :actual] / total_hitters
	stats[[9, 10], :actual] = stats[[9, 10], :actual] / total_pitchers

	# calculate delta
	stats[:, :delta] = stats[:, :actual] - stats[:, :target]

	# display df
	stats
end

# ╔═╡ 98a2dc95-43fc-4ae4-81fb-44d2273d8d30
md"""
Almost all of our objectives have been satisfied. `OBP` is a little below target, but this is because of the adjustment we had to make to our targets to keep the model linear. Both pitching ratios actually beat the target set for them, so in those cases our approximation worked.

It looks like `SB` and `SO` are two categories with a strong surplus. For strikeouts, this makes sense based on the emphasis on starting pitching in the early draft rounds. Most of the offensive players drafted have non-zero speed, so the model seemed to prioritize that player profile throughout the draft.

We can see that a player was selected in every round and no two players were selected twice, but let's double check that the positional requirements have been met:
"""

# ╔═╡ 9f89d124-7e00-4d01-ac9b-9bb0f150a3ab
begin
	# create pos df
	pos = DataFrame((
		position = [p for p ∈ keys(position_min)],
		target = [position_min[p] for p ∈ keys(position_min)],
		actual = [sum(drafted_players_df[:, p]) for p ∈ keys(position_min)]
	))

	# calculate delta
	pos[:, :delta] = pos[:, :actual] - pos[:, :target]

	# display df
	pos
end

# ╔═╡ 8f939cb9-2179-4f8b-a655-0a6f9bba4302
md"""
All of the positional constraints have been met. It seems the model chose extra SS- and OF-eligible players.

Now let's look to our final draft constraints, *ADPOddMax* and *ADPEvenMax*. These are meant to mimic the snake draft and ensure that no player is selected after their `ADP`.
"""

# ╔═╡ 14b7b569-fe4f-4655-8fa0-653fa0c1e396
begin
	odd = [teams * (j - 1) + start_position for j=1:2:25]
	even = [teams * (j - 2) + start_position + 1 for j=2:2:24]
	draft_picks = sort(vcat(even, odd))
	drafted_players_df[:, :Pick] = draft_picks
end

# ╔═╡ 107ae882-1d26-437f-b215-d7744aa6d457
show(select(drafted_players_df, [:Pick, :ADP, :player]), allrows=true)

# ╔═╡ 242b7a0f-3c88-45f6-a23a-97f22f48e3d5
md"""
We can confirm that no player was selected with a pick that was after their `ADP`. The majority of the players are actually selected well before their `ADP`. This is especially true in the first two rounds with Zack Wheeler and Luis Castillo. I am confident that these players would be available when the model chose to select them; however, there are others that I would deem high-risk selections. These players were taken very close to their `ADP`:

* Camilo Doval
* Kyle Schwarber
* Logan O'Hoppe
* Jose Berrios

It is highly probable that some of these players will be selected prior to when the model decided to draft them in a real-world situation. We will address how this might impact our roster with scenario analysis.
"""

# ╔═╡ a97621b8-2cbf-45bf-a4f0-52c28539159f
md"""
## Next Steps
In the [next analysis](https://github.com/jwnorm/fantasy_draft/blob/main/model/julia/scenario.html), we will walk through how different scenarios impact the optimal fantasy baseball draft we just solved above.
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
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

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
# ╟─34aabfbf-46a7-48ed-8696-baab5a06d5b5
# ╟─73b5ff4b-f74b-442f-9679-f7023f5bc4a2
# ╟─89176410-3afb-49ca-b296-a5e510f147d2
# ╠═05c61bd0-e94b-11ee-0448-ab92a4e36eb7
# ╟─46e54092-e74c-4d2c-853a-59a0489667ba
# ╠═068cb0f0-1c0f-421d-8d56-5707be32e9dc
# ╟─0712c423-262c-46e7-b996-2be27e79d669
# ╠═01875dcf-f38a-407c-8691-f08952e29283
# ╟─8930bbad-ff16-464b-9236-4dd8ac78d500
# ╠═1ebf6238-68e0-4965-8f52-94dcf724c88a
# ╟─609ad202-fb66-45d4-a308-56acef5e4270
# ╠═d5dc21ba-f8f7-490f-91fa-fc549d2f9aec
# ╟─efdfd4d2-596c-44d9-978b-4d2e541d35b5
# ╟─334c0497-e812-43ac-bbcc-63c3fa5c3b87
# ╠═ea49bdfa-a22b-4156-a664-ed7dc2a3f5f4
# ╟─e5ebadec-b2f2-4fa5-8666-d56e8346bb39
# ╠═f991061a-2be5-4563-93f8-2f1f7730fee1
# ╟─96b7d9be-0013-4f9d-a300-6e319789f7fe
# ╠═e243dd01-d94f-48ab-bf5a-a9077e62c2ba
# ╟─24324454-e644-4a56-bdc1-2f8e64e8d03e
# ╠═dcf57186-b704-4a91-97d9-3a8b9d63711a
# ╟─29e9d160-8ace-48ba-b314-1a4a6dd188ea
# ╠═4f6ceaac-e93e-480d-a37e-595e53f6cf83
# ╟─78530e8d-e32d-4154-b913-c9a8745e05ec
# ╠═6e00d682-8c4e-4250-a6e5-d4383e7caae6
# ╟─e2b12d7d-df7e-4d9e-b095-705d486e5388
# ╠═258ffcba-e4f2-483f-8173-53e3051af4cd
# ╟─890d0a70-c6d8-41d2-95c8-dd2ee0d8b78f
# ╠═e2911ffd-d89b-4004-8749-b42d116ac841
# ╟─7cfdd204-5a2b-40fb-9381-d6b600edfe9e
# ╠═1c11428a-748b-4438-8dca-0e6f684343ad
# ╟─255d8fd3-15a5-47d7-96d0-203cb0f4fc30
# ╠═f2e2cd8e-59c8-452d-bf12-0e6181e6c2c5
# ╟─4b00b875-9516-46de-8d2e-22bc8733334d
# ╠═3b3ef5fa-b3e8-4710-9fed-c60aa991f98a
# ╟─952b73e1-d052-4188-afd4-896bb754ec4c
# ╠═c0b8e207-3b0d-4265-93b4-dbc607ad9f9b
# ╟─f189408f-5231-47e5-9746-5b2cb3ad0e50
# ╟─6e59a964-ea5c-4159-b4d2-99d514ab033f
# ╟─0560224e-d385-430c-807e-4131b91fcd1c
# ╠═1d96d749-ff96-49aa-89af-372ff61d1504
# ╟─b59b5fe4-6bb5-4549-aaad-494594c915de
# ╠═290baa5c-8975-4db5-9d9f-9b5927cc42f7
# ╟─e0f87ac8-3bb4-4bd8-94da-42ec587622ba
# ╠═5e97a550-6461-4a02-ab72-16847ca20182
# ╟─82af4416-ce57-4ac5-af25-d684de12085f
# ╠═8ee31704-9e55-4f6a-bafe-8eda6259c7ab
# ╟─12d1a9fa-43bf-4377-8629-65491080695d
# ╠═9149e595-0f96-4240-98bc-b42fdf45a8ed
# ╟─98a2dc95-43fc-4ae4-81fb-44d2273d8d30
# ╠═9f89d124-7e00-4d01-ac9b-9bb0f150a3ab
# ╟─8f939cb9-2179-4f8b-a655-0a6f9bba4302
# ╠═14b7b569-fe4f-4655-8fa0-653fa0c1e396
# ╠═107ae882-1d26-437f-b215-d7744aa6d457
# ╟─242b7a0f-3c88-45f6-a23a-97f22f48e3d5
# ╟─a97621b8-2cbf-45bf-a4f0-52c28539159f
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
