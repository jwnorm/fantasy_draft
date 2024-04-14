* Fantasy Baseball Draft - Small Scale Example - Condensed Parameters

Sets
i 'players'
/
"Ronald Acuña Jr."
"Mookie Betts"
"Aaron Judge"
"Juan Soto"
"Fernando Tatis Jr."
"Adley Rutschman"
"Yordan Alvarez"
"Bobby Witt Jr."
"Corey Seager"
"Will Smith"
"Julio Rodríguez"
"Shohei Ohtani"
"José Ramírez"
"Freddie Freeman"
"Austin Riley"
"Alex Bregman"
"Corbin Carroll"
"Rafael Devers"
"Gunnar Henderson"
"Mike Trout"
"Francisco Lindor"
"Vladimir Guerrero Jr."
"Sean Murphy"
"William Contreras"
"Kyle Tucker"
"Trea Turner"
"Bryce Harper"
"Marcus Semien"
"Dansby Swanson"
"Matt Olson"
"Cal Raleigh"
"Matt Chapman"
"Ketel Marte"
"Gleyber Torres"
"Michael Harris II"
"Jose Altuve"
"J.T. Realmuto"
"Manny Machado"
"Jonah Heim"
"Willy Adames"
/

j 'round in draft' /1*5/

k 'statistic'
/
hr
r
rbi
sb
/
;

Parameters
ADP(i) 'average draft position for player i in similar 12-team leagues'
/
"Ronald Acuña Jr." 1
"Mookie Betts"  5
"Aaron Judge"   11.4
"Juan Soto" 10.7
"Fernando Tatis Jr."    7.9
"Adley Rutschman"   53.8
"Yordan Alvarez"    16.4
"Bobby Witt Jr."    2.4
"Corey Seager"  31.7
"Will Smith"    84.3
"Julio Rodríguez"   3.1
"Shohei Ohtani" 12.7
"José Ramírez"  16.2
"Freddie Freeman"   8.7
"Austin Riley"  19.2
"Alex Bregman"  97.8
"Corbin Carroll"    6
"Rafael Devers" 24.1
"Gunnar Henderson"  32.9
"Mike Trout"    71
"Francisco Lindor"  23
"Vladimir Guerrero Jr." 29.8
"Sean Murphy"   141.4
"William Contreras" 78
"Kyle Tucker"   6.5
"Trea Turner"   12.4
"Bryce Harper"  17.7
"Marcus Semien" 31.1
"Dansby Swanson"    120.4
"Matt Olson"    17.1
"Cal Raleigh"   138.1
"Matt Chapman"  275.9
"Ketel Marte"   119.3
"Gleyber Torres"    83.3
"Michael Harris II" 28.7
"Jose Altuve"   42.9
"J.T. Realmuto" 73.3
"Manny Machado" 64.1
"Jonah Heim"    173.2
"Willy Adames"  183
/


PosC(i) 'whether or not player i is catcher-eligible'
/
"Ronald Acuña Jr."  0
"Mookie Betts"  0
"Aaron Judge"   0
"Juan Soto" 0
"Fernando Tatis Jr."    0
"Adley Rutschman"   1
"Yordan Alvarez"    0
"Bobby Witt Jr."    0
"Corey Seager"  0
"Will Smith"    1
"Julio Rodríguez"   0
"Shohei Ohtani" 0
"José Ramírez"  0
"Freddie Freeman"   0
"Austin Riley"  0
"Alex Bregman"  0
"Corbin Carroll"    0
"Rafael Devers" 0
"Gunnar Henderson"  0
"Mike Trout"    0
"Francisco Lindor"  0
"Vladimir Guerrero Jr." 0
"Sean Murphy"   1
"William Contreras" 1
"Kyle Tucker"   0
"Trea Turner"   0
"Bryce Harper"  0
"Marcus Semien" 0
"Dansby Swanson"    0
"Matt Olson"    0
"Cal Raleigh"   1
"Matt Chapman"  0
"Ketel Marte"   0
"Gleyber Torres"    0
"Michael Harris II" 0
"Jose Altuve"   0
"J.T. Realmuto" 1
"Manny Machado" 0
"Jonah Heim"    1
"Willy Adames"  0
/

Target(k)   'targets for metric k'
/
hr      100
r       400
rbi     250
sb      50
/
;

Table m(i, k)   'metric k for player i'
$ondelim
$include data.csv
$offdelim
;

Scalars
DP          'draft position in round 1' /6/
Teams       'number of teams in draft'  /12/
Catcher     'minimum number of catchers on roster' /1/
;

Variables
z                  'objective function variable - sum of normalized category deviation'
x(i, j)            'whether or not player i is selected in the jth round of the draft'
Metric_delta(k)    'deviation for metric k'
;

Binary variable x;
Free variable Metric_delta(k);

Equations
Objective       'objective function variable - sum of normalized category deviation'
MetricGoal(k)   'goal function for metric k'
RoundMax(j)     'one pick per round'
PlayerMax(i)    'unique player can only be selected once'
ADPMax(j)       'player must be taken after their ADP'
CatcherMin      'player must be taken after their ADP'
;

Objective..         z                                                       =e=     sum(k, Metric_delta(k) / Target(k));
MetricGoal(k)..     sum((i, j), m(i, k) * x(i, j)) - Metric_delta(k)        =e=     Target(k); 
RoundMax(j)..       sum(i, x(i, j))                                         =e=     1;
PlayerMax(i)..      sum(j, x(i, j))                                         =l=     1;
ADPMax(j)..         sum(i, ADP(i) * x(i, j))                                =g=     Teams * (j.pos-1) + DP;
CatcherMin..        sum((i, j), PosC(i) * x(i, j))                          =e=     Catcher;

Model fantasy_draft /all/;

Solve fantasy_draft using mip maximizing z;

Parameters
TotalMetric(k)    'total of metric k'
;

TotalMetric(k)     = Target(k) + Metric_delta.l(k);

Option x:0:1:1, TotalMetric:0;
Display z.l, x.l, TotalMetric;
