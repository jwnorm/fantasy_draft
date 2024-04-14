* Fantasy Baseball Draft - Counting Stats Model
Sets
i 'players'
/
$include players.txt
/

j 'round in draft' /1*9/

k 'statistical category'
/
HR
R
RBI
SB
W
SOLD
SO
/

p ' position on field'
/
PosC
Pos1B
Pos2B
Pos3B
PosSS
PosINF
PosOF
PosUT
PosP
/
;


Parameters
ADP(i)   'metric k for player i'
/
$include adp.txt
/

Target(k)   'target minimum value for category k'
/
HR      275
R       1000
RBI     1500
SB      200
W       100
SOLD    150
SO      1500
/


MinPos(p) 'min number of players on roster eligible for position p'
/
PosC    1
Pos1B   1
Pos2B   1
Pos3B   1
PosSS   0
PosINF  0
PosOF   1
PosUT   0
PosP    1
/   
;

Table
Category(i, k)      'metric k for player i'
$ondelim
$include stats.csv
$offdelim
;

Table
Position(i, p)     'position p eligibility for player i'
$ondelim
$include positions.csv
$offdelim
;

Scalars
DP      'starting draft position'   /12/
Teams   'number of teams in league' /12/
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
*ADPMax(j)..     'player must be taken after their ADP'
ADPEvenMax(j)   'Even rounds - player must be taken after their ADP'
ADPOddMax(j)    'Odd rounds - player must be taken after their ADP'
PositionMin(p)  'minimum number of players eligible for position p on r'
;

Objective..                             z                                                                   =e=     sum(k, Metric_delta(k) / Target(k));
MetricGoal(k)..                         sum((i, j), Category(i, k) * x(i, j)) - Metric_delta(k)             =e=     Target(k); 
RoundMax(j)..                           sum(i, x(i, j))                                                     =e=     1;
PlayerMax(i)..                          sum(j, x(i, j))                                                     =l=     1;
*ADPMax(j)..                            sum(i, ADP(i) * x(i, j))                                            =g=     Teams * (j.pos - 1) + DP;
ADPEvenMax(j)$(mod(j.pos,2) = 0)..      sum(i, ADP(i) * x(i, j))                                            =g=     Teams * (j.pos - 2) + (DP + 1);
ADPOddMax(j)$(mod(j.pos,2) = 1)..       sum(i, ADP(i) * x(i, j))                                            =g=     Teams * (j.pos - 1) + DP;
PositionMin(p)..                        sum((i, j), Position(i, p) * x(i, j))                               =g=     MinPos(p);

Model fantasy_draft /all/;

Solve fantasy_draft using mip maximizing z;

Parameters
TotalMetric(k)    'total of metric k'
;

TotalMetric(k)     = Target(k) + Metric_delta.l(k);

Option x:0:1:1, TotalMetric:0;
Display z.l, x.l, TotalMetric;
