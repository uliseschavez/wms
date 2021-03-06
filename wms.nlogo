globals
[
  grid-x-inc               ;; the amount of storage patches in the x direction
  grid-y-inc               ;; the amount of storage patches in the y direction
  consumption-inc          ;; the amount of consumption-areas
  percent-occupy-storage   ;; what percent of storage is occupy
  total-displacement       ;; total displacment covered by all the lifters
  tarrived
  tstored
  tconsumed
  
  ;; patch areas
  arrival-area             ;; area for arrival
  consumption-area         ;; area for consumption
  consumption-area-paths   ;; paths for consumption area
  
  ;; patch agentset
  storage ;;agentset containing the patches that are storages
  paths   ;;agentset containing the patches that are not storages
  consum  ;;agentset containing the patches that are consumers
  
  ;; helper agentsets
  assigned   ;;boxes that have already being allocated
  unassigned ;;boxes that are ready for storage assignation
  unoccupied ;;patches that can hold a box
  boxes-with-type ;;boxes that have the same type as the next order
  stored     ;;boxes that are already in the storage area
  free       ;;available patches in teh consuption-area
  
  avg-utility
  
]

breed [ boxes box ]
boxes-own
[
  priority
  product
]

breed [ lifters lifter ]
lifters-own
[
  task-list
  subtask
  ;curr-box
  ;curr-dest
]

patches-own
[
  product_type
  ;utility
]

;breed [ consumers consumer ]
;consumers-own
;[
;  product_type
;]

to setup
  clear-all
  setup-globals
  setup-patches
  setup-turtles
  do-plots
end

to do
  new-arrivals
  store-arrivals
  select-for-consumption
  consume
  do-lifter-task
  tick
  calculate-percentage
  calculate-tstored
  do-plots
  shift-priorities
  if turn-negotiation [ 
    if ticks mod 100 = 0 [ negotiation ]
  ]
  if ticks = 1000 [stop] 
end

to setup-globals
  set-default-shape boxes "box"
  set-default-shape lifters "truck"
  
  set grid-x-inc 16 / grid-size-x
  set grid-y-inc world-height / grid-size-y
  set consumption-inc world-height / consumption-areas 
  set avg-utility 0
end

;; Make the patches have appropriate colors, set up the storage agentset and consumer agentsets,
to setup-patches
  ;; initialize the global variables that hold patch areas
  set arrival-area patches with
    [pxcor < 8]
  set consumption-area patches with
    [pxcor > 25]
  set consumption-area-paths patches with
    [(floor((pycor + max-pycor - floor(consumption-inc - 1)) mod consumption-inc) = 0) and (pxcor > 24) or (pxcor = 25) or (pxcor = max-pxcor) ]
  set paths patches with
    [(floor((pxcor + 7 - floor(grid-x-inc - 1)) mod grid-x-inc) = 0) or
    (floor((pycor + max-pycor - floor(grid-y-inc - 1)) mod grid-y-inc) = 0) or
    pycor = max-pycor and (pxcor > 7) and (pxcor < 25)]
  
    
  ask arrival-area [
    set pcolor white set product_type 0
    ]
  ask consumption-area [set pcolor yellow]
  ask consumption-area-paths [ set pcolor brown set product_type 0] 
  ask paths [ set pcolor gray set product_type 0]
  
  ;; initialize the global variables that hold the storage agentset
  set storage patches with [ pcolor = black ]
  set consum patches with [ pcolor = yellow ]
  ask consum [
    let product_no consumption-areas
    while [product_no > 0]
    [
    if pycor <= consumption-inc * product_no and pycor > consumption-inc * (product_no - 1)  [ set product_type product_no ]
    set product_no product_no - 1
    ]
  ]
  ;ask patches [ set utility 0 ]
  
end

to setup-turtles
  create-boxes initial-boxes
  ask boxes
  [
    ;set priority random 10
    set product random consumption-areas + 1
    set priority consumption-areas - abs (product - priority-shift)
    ifelse start-at-storage
    [ move-to one-of storage with [ not any? other turtles-here ] ]
    [ move-to one-of arrival-area with [ not any? other turtles-here ] ]
    set label product
    ;set color brown
  ]
  
  create-lifters n-of-lifters [
    set color red
    move-to one-of paths with [ not any? lifters-here ]
    set subtask 0
    set task-list []
    set label who
  ]
end

to shift-priorities
end

to new-arrivals
  if ticks mod arrival-rate = 0 [
    create-boxes arrival-quantity  [
      set product random consumption-areas + 1
      set priority consumption-areas - abs (product - priority-shift)
      ifelse any? arrival-area with [ not any? other turtles-here ]
      [ move-to one-of arrival-area with [ not any? other turtles-here ]
        set tarrived tarrived + 1 ]
      [ user-message (word "maximum occupancy reached")]
      set label product
    ]
  ]
end

to store-arrivals
  ;cn-arrivals
  if storage-method = "cn-arrivals"
      [cn-arrivals]
  if storage-method = "cn-combined"
      [ ifelse count boxes-on arrival-area >= n-of-lifters
        [ cn-combined ]
        [ cn-arrivals ]
      ]
  if storage-method = "random"
      [random-storage]
  if storage-method = "nearest"
      [nearest-storage]
  if storage-method = "arrival"
      [arrival-storage]
  if storage-method = "classified"
      [classified-storage]
      
end

to select-for-consumption
  if ticks mod consumption-rate = 0
  [
    if consumption-method = "cn-consumption"
      [cn-consumption]
    if consumption-method = "cn-combined"
      [ ifelse count boxes-on storage >= n-of-lifters
        [ cn-consumption-combined ]
        [ cn-consumption ]
      ]
    if consumption-method = "random"
    [random-consumption]
  ]
end

to cn-arrivals
  set unassigned boxes-on arrival-area
  if any? unassigned with [ not any? my-in-links ]
  [
    set unoccupied storage with [ not any? boxes-here ]
    ;ask unoccupied
    ;[
      ask max-one-of unassigned [ priority ]
      [
        let storage-type product
        let destination min-one-of unoccupied [distance one-of consum with [ product_type = storage-type ] ]
        let target self
        if any? patch-set destination [
          ifelse lifters-available
          [
            if not any? my-in-links [
              let dist-to-dest distance destination
              
            let worker one-of lifters
            if lifter-criteria = "closest" [ set worker min-one-of lifters [ distance self ] ]
            if lifter-criteria = "workload" [ set worker min-one-of lifters [ length task-list ] ]
            ask worker
              [ 
                create-link-to target
                let cost distance target + dist-to-dest
                set task-list lput (list target destination cost) task-list
              ]
            ]
          ]
          [
            set tstored tstored + 1
            move-to destination
          ]
        ]
      ]
  ]
end

to cn-combined
  set unassigned boxes-on arrival-area
  if any? unassigned with [ not any? my-in-links ]
  [
    set unoccupied storage with [ not any? boxes-here ]
    ;ask unoccupied
    ;[
      ask max-n-of n-of-lifters unassigned [ priority ]
      [
        let storage-type product
        let destination min-one-of unoccupied [distance one-of consum with [ product_type = storage-type ] ]
        let target self
        if any? patch-set destination [
          ifelse lifters-available
          [
            if not any? my-in-links [
              let dist-to-dest distance destination
              
            let worker one-of lifters
            if lifter-criteria = "closest" [ set worker min-one-of lifters [ distance self ] ]
            if lifter-criteria = "workload" [ set worker min-one-of lifters [ length task-list ] ]
            ask worker
              [ 
                create-link-to target
                let cost distance target + dist-to-dest
                set task-list lput (list target destination cost) task-list
              ]
            ]
          ]
          [
            set tstored tstored + 1
            move-to destination
          ]
        ]
      ]
  ]
end

to cn-consumption
  set stored boxes-on storage
  if any? stored
  [
    ask max-one-of stored [ priority ] 
      [
        let consum-type product
        let destination one-of consum with [ not any? boxes-here and product_type = consum-type ]
        let target self
        
        if any? patch-set destination [
          ifelse lifters-available
          [
            if not any? my-in-links [
              let dist-to-dest distance destination
              
              let worker one-of lifters
              if lifter-criteria = "closest" [ set worker min-one-of lifters [ distance self ] ]
              if lifter-criteria = "workload" [ set worker min-one-of lifters [ length task-list ] ]
              ask worker
              [
                create-link-to target
                let cost distance target + dist-to-dest
                set task-list lput (list target destination cost) task-list
              ]
            ]
          ]
          [ 
            set tstored tstored + 1
            move-to destination
          ]
        ]
      ]
  ]
end

to cn-consumption-combined
  set stored boxes-on storage
  if any? stored
  [
    ask max-n-of n-of-lifters stored [ priority ] 
      [
        let consum-type product
        let destination one-of consum with [ not any? boxes-here and product_type = consum-type ]
        let target self
        
        if any? patch-set destination [
          ifelse lifters-available
          [
            if not any? my-in-links [
              let dist-to-dest distance destination
              
              let worker one-of lifters
              if lifter-criteria = "closest" [ set worker min-one-of lifters [ distance self ] ]
              if lifter-criteria = "workload" [ set worker min-one-of lifters [ length task-list ] ]
              ask worker
              [
                create-link-to target
                let cost distance target + dist-to-dest
                set task-list lput (list target destination cost) task-list
              ]
            ]
          ]
          [ 
            set tstored tstored + 1
            move-to destination
          ]
        ]
      ]
  ]
end

to random-consumption
  set stored boxes-on storage
  if any? stored
  [
    ask one-of stored
    [
        let consum-type product
        let destination one-of consum with [ not any? boxes-here and product_type = consum-type ]
        let target self
        
        if any? patch-set destination [
          ifelse lifters-available
          [
            if not any? my-in-links [
              let dist-to-dest distance destination
              
              let worker one-of lifters
              if lifter-criteria = "closest" [ set worker min-one-of lifters [ distance self ] ]
              if lifter-criteria = "workload" [ set worker min-one-of lifters [ length task-list ] ]
              ask worker
              [
                create-link-to target
                let cost distance target + dist-to-dest
                set task-list lput (list target destination cost) task-list
              ]
            ]
          ]
          [ 
            set tstored tstored + 1
            move-to destination
          ]
        ]
    ]
  ]
end

to consume
  if ticks mod consumption-rate = 0
  [
    ;let next-type random consumption-areas + 1
    let product-list n-values consumption-areas [ ? + 1]
    foreach product-list [
      ask one-of consum with [product_type = ? ]
      [
        let to-be-consumed one-of boxes-here with [ not any? my-in-links ]
        if any? turtle-set to-be-consumed
        [
          ask to-be-consumed [ 
            set avg-utility avg-utility + priority
            set tconsumed tconsumed + 1
            die
          ]
        ]
      ]
    ]
  ]
end

to do-lifter-task
  ;let frontier []
  
  ;if activate-negotiation [
  ;  zeuthen
  ;]
  
  ask lifters [
    ;ask neighbors4 [
     ; set frontier lput self frontier
    ;]
    
    if not empty? task-list [
      let target first first task-list
      let target-patch patch [xcor] of target [ycor] of target
      let destination item 1 first task-list
       
      if subtask = 0 [
        ;create-link-to target
        face min-one-of (neighbors4 with [pcolor != black]) [distance target]
        fd 1
        set subtask 1
      ]
      
      if subtask = 1 [
        ;ifelse xcor != [xcor] of target or ycor != [ycor] of target
        ;ifelse patch-ahead 1 != target-patch
        ;[
          let frontier (patch-set patch-ahead 1 patch-left-and-ahead 90 1 patch-right-and-ahead 90 1)
          ifelse member? target-patch frontier
          [ 
            face target-patch
            set subtask 2
          ]
          [
            face min-one-of (frontier) [distance target]
            fd 1
          ]
        ;]
        ;[
         ; fd 1
          ;set subtask 2
        ;]
      ]
      
      if subtask = 2 [
        ifelse any? link-set link [who] of self [who] of target [
          ask link [who] of self [who] of target [ tie ] ;set endpoint1 end1 set endpoint2 end2 ]
          face min-one-of (neighbors4 with [pcolor != black]) [distance destination]
          fd 1
          set subtask 3
        ] 
        [ 
          set task-list but-first task-list
          set subtask 0 
        ]
      ]
      if subtask = 3 [
        ;ifelse patch-ahead 1 != destination ;xcor != [xcor] of destination and ycor != [ycor] of destination ]
        ;[
          let frontier (patch-set patch-ahead 1 patch-left-and-ahead 90 1 patch-right-and-ahead 90 1)
          ifelse member? destination frontier
          [ 
            face destination
            if any? link-set link [who] of self [who] of target
              [ 
                ask link [who] of self [who] of target [ untie die ] 
                set total-displacement total-displacement + last first task-list 
              ]                    
            set task-list but-first task-list
            set subtask 0
            ]
          [ face min-one-of (frontier with [pcolor != black]) [distance destination] fd 1]
          ;fd 1
          ;face destination
      ]
    ]
  ]
end

to zeuthen
end


;;Stores the boxes randomly in any available space in the storage area
to random-storage
  set unassigned boxes-on arrival-area
  if any? unassigned
  [
    set unoccupied storage with [ not any? boxes-here ]
      ask one-of unassigned
      [
        let destination one-of unoccupied
        let target self
        
        ifelse lifters-available
        [
          if not any? my-in-links [
            let dist-to-dest distance destination
            let worker one-of lifters
            if lifter-criteria = "closest" [ set worker min-one-of lifters [ distance self ] ]
            if lifter-criteria = "workload" [ set worker min-one-of lifters [ length task-list ] ]
            ask worker
            [
              create-link-to target
              let cost distance target + dist-to-dest
              set task-list lput (list target destination cost) task-list
            ]
          ]
        ]
        [
          set tstored tstored + 1
          move-to destination
        ]
      ]
  ]
end

;;Stores the boxes in the nearest available space from arrival
to arrival-storage
  set unassigned boxes-on arrival-area
  if any? unassigned
  [
    set unoccupied storage with [ not any? boxes-here ]
      ask max-one-of unassigned [ priority ]
      [
        let destination min-one-of unoccupied [ distance myself ]
        let target self
        
        ifelse lifters-available
        [
          if not any? my-in-links [
            let dist-to-dest distance destination
            
            ask min-one-of lifters [ distance self ]
            [
              create-link-to target
              let cost distance target + dist-to-dest
              set task-list lput (list target destination cost) task-list
            ]
          ]
        ]
        [
          set tstored tstored + 1
          move-to destination
        ]
      ]
  ]
end

;;Stores the boxes in the available space closest to any stored boxed
to nearest-storage
  set unassigned boxes-on arrival-area
  set stored boxes-on storage
  if any? unassigned
  [
    set unoccupied storage with [ not any? boxes-here ]
    if any? unoccupied
    [
      ask max-one-of unassigned [ priority ]
      [
        let destination one-of unoccupied
        if any? stored
        [ set destination min-one-of unoccupied [ distance one-of stored ] ]
        let target self
        
        ifelse lifters-available
        [
          if not any? my-in-links [
            let dist-to-dest distance destination
            
            ask min-one-of lifters [ distance self ]
            [
              create-link-to target
              let cost distance target + dist-to-dest
              set task-list lput (list target destination cost) task-list
            ]
          ]
        ]
        [
          set tstored tstored + 1
          move-to destination
        ]
      ]
    ]
  ]
end

;;Stores the boxes in the nearest available space to another stored box of same charateristic, in this case of same color. 
to classified-storage2
  set unassigned boxes-on arrival-area
  set stored boxes-on storage
  if any? unassigned
  [
    set unoccupied storage with [ not any? boxes-here ]
      ask max-one-of unassigned [ priority ]
      [
        let c [color] of self
        let target self
        ifelse lifters-available
        [
          let destination one-of unoccupied
          if any? stored with [color = c]
          [ set destination min-one-of unoccupied [distance one-of stored with [color = c ] ] ]
          if not any? my-in-links [
          let dist-to-dest distance destination
              
          ask min-one-of lifters [ distance self ]
            [
              create-link-to target
              let cost distance target + dist-to-dest
              set task-list lput (list target destination cost) task-list
            ] 
          ]
        ]
        [   
          ifelse any? stored with [color = c]
          [move-to (min-one-of unoccupied [distance one-of stored with [color = c ]])]
          [move-to one-of unoccupied]
          set tstored tstored + 1
        ]
      ]
  ]
end

to classified-storage
  set unassigned boxes-on arrival-area
  set stored boxes-on storage
  if any? unassigned
  [
    set unoccupied storage with [ not any? boxes-here ]
      ask max-one-of unassigned [ priority ]
      [
        let p [product] of self
        let target self
        ifelse lifters-available
        [
          let destination one-of unoccupied
          if any? stored with [product = p]
          [ set destination min-one-of unoccupied [distance one-of stored with [product = p ] ] ]
          if not any? my-in-links [
          let dist-to-dest distance destination
              
          ask min-one-of lifters [ length task-list ]
            [
              create-link-to target
              let cost distance target + dist-to-dest
              set task-list lput (list target destination cost) task-list
            ] 
          ]
        ]
        [   
          ifelse any? stored with [product = p]
          [move-to (min-one-of unoccupied [distance one-of stored with [product = p]])]
          [move-to one-of unoccupied]
          set tstored tstored + 1
        ]
      ]
  ]
end

to negotiation
  ask one-of lifters ;[ length task-list ]
  [
    let u 0
    foreach task-list [ set u u + item 2 ? ]
    let tasks task-list
    let other-tasks []
    let working-lifter max-one-of lifters [ length task-list ]
    ask working-lifter
    [
      set other-tasks task-list
    ]
    
    let i 0
    foreach other-tasks [
      let target first ?
      let destination item 1 ?
      let cost distance target
      ask target [ set cost cost + distance destination ]
      
      let new-task-cost replace-item 2 ? cost
      set other-tasks replace-item i other-tasks new-task-cost
      set i i + 1
      ;set ? replace-item 2 ? cost
    ]
    
    set tasks sentence tasks other-tasks
    
    let delta []
    set i 0
    while [ i <= length tasks ] 
    [
      let delta1 sublist tasks 0 i
      let delta2 sublist tasks i length tasks
      ;if not empty? delta1 [ set delta1 reduce [ (sentence ?1) ] delta1 ]
      ;if not empty? delta2 [ set delta2 reduce [ (sentence ?1) ] delta2 ]
      set delta lput (list delta1 delta2) delta
      set i i + 1
    ]
    
    let other-delta delta
    
    let delta-costs []
    foreach delta [
      let cost 0
      ;if any? set cost cost + last first ?
      foreach first ? [ 
        if not empty? ? [set cost cost + last ?]
      ]
      set delta-costs lput cost delta-costs
    ]

    set i 0
    foreach delta-costs [
      let next-delta item i delta
      set next-delta lput (u - ?) next-delta
      set delta replace-item i delta next-delta
      set i i + 1
    ]
    
    let delta-costs2 []
    ask working-lifter [
      foreach other-delta [
        let cost 0
        foreach first ? [
          if not empty? ? [set cost cost + last ?]
        ]
        set delta-costs2 lput cost delta-costs2
      ]
      
      set i 0
      foreach delta-costs2 [
        let next-delta item i other-delta
        set next-delta lput (u - ?) next-delta
        set other-delta replace-item i delta next-delta
        set i i + 1
    ]
    
    set delta sort-by [ last ?1 > last ?2 ] delta 
    set other-delta sort-by [ last ?1 > last ?2 ] other-delta ]
    
    let my-deal first delta
    let other-deal first other-delta
    
    while [ last other-deal < last my-deal ] [
      set delta butfirst delta
      set other-delta butfirst other-delta
      set my-deal first delta
      set other-deal first other-delta
    ]
    set my-deal butlast my-deal
    
    show task-list
    show my-deal
  
    set task-list first my-deal
    if any? my-out-links [
      ask my-out-links [
        untie
        die
      ]
    ]
    ask working-lifter [
      if any? my-out-links [
        ask my-out-links [
          untie
          die
        ]
      ]
      set task-list last my-deal
    ]
  ] 
end

;; Calculates the percentage of occupied storage 
to calculate-percentage
    set percent-occupy-storage 100 - (((count unoccupied)/ (count storage)) * 100)
end

to calculate-tstored
  let cstored count boxes-on storage
  let cconsume count boxes-on consumption-area
  set tstored (cstored + cconsume  + tconsumed)
end

to do-plots
  set-current-plot "Totals"
  set-current-plot-pen "arrival"
  plot count boxes-on arrival-area
  set-current-plot-pen "storage"
  plot count boxes-on storage
  set-current-plot-pen "consume"
  plot count boxes-on consumption-area
  set-current-plot "Utility"
  set-current-plot-pen "avg-utility"
  plot avg-utility * 100 / (ticks + 1)
end


@#$#@#$#@
GRAPHICS-WINDOW
246
10
685
366
-1
-1
13.0
1
10
1
1
1
0
0
0
1
0
32
0
24
1
1
1
ticks

BUTTON
100
14
166
47
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL

SLIDER
9
215
181
248
grid-size-x
grid-size-x
1
8
8
1
1
NIL
HORIZONTAL

SLIDER
9
253
181
286
grid-size-y
grid-size-y
1
10
10
1
1
NIL
HORIZONTAL

SLIDER
8
292
180
325
consumption-areas
consumption-areas
1
10
3
1
1
NIL
HORIZONTAL

SLIDER
8
331
180
364
initial-boxes
initial-boxes
0
100
70
1
1
NIL
HORIZONTAL

SWITCH
23
55
169
88
start-at-storage
start-at-storage
1
1
-1000

BUTTON
22
14
85
47
NIL
do
T
1
T
OBSERVER
NIL
NIL
NIL
NIL

CHOOSER
30
98
168
143
storage-method
storage-method
"cn-arrivals" "cn-combined" "random" "nearest" "arrival" "classified"
5

MONITOR
707
13
764
58
arrived
tarrived
0
1
11

MONITOR
777
13
834
58
stored
tstored
0
1
11

MONITOR
846
13
946
58
consumed
tconsumed
0
1
11

MONITOR
707
73
779
118
% storage
percent-occupy-storage
2
1
11

PLOT
707
135
978
342
Totals
time
totals
0.0
10.0
0.0
110.0
true
true
PENS
"arrival" 1.0 0 -2674135 true
"storage" 1.0 0 -16777216 true
"consume" 1.0 0 -10899396 true

SLIDER
196
53
229
203
arrival-rate
arrival-rate
0
100
50
1
1
NIL
VERTICAL

SLIDER
196
214
229
364
consumption-rate
consumption-rate
1
100
20
1
1
NIL
VERTICAL

INPUTBOX
196
374
281
434
arrival-quantity
10
1
0
Number

SLIDER
9
428
181
461
n-of-lifters
n-of-lifters
0
20
10
1
1
NIL
HORIZONTAL

SWITCH
12
380
164
413
lifters-available
lifters-available
0
1
-1000

MONITOR
792
72
877
117
displacement
total-displacement
3
1
11

SLIDER
514
377
686
410
priority-shift
priority-shift
1
consumption-areas
3
1
1
NIL
HORIZONTAL

PLOT
718
382
918
532
Utility
time
utility
0.0
10.0
0.0
0.5
true
false
PENS
"default" 1.0 0 -16777216 true
"avg-utility" 1.0 0 -16777216 true

CHOOSER
34
478
172
523
lifter-criteria
lifter-criteria
"closest" "random" "workload"
1

CHOOSER
24
157
185
202
consumption-method
consumption-method
"random" "cn-consumption" "cn-combined"
0

SWITCH
214
463
375
496
turn-negotiation
turn-negotiation
0
1
-1000

@#$#@#$#@
WHAT IS IT?
-----------
In a warehouse you need to manage incoming/outgoing products, storage capacity and product replenishment, overall maintain the product flow whit in the installations. Here we try to simulate this implementing agents utilizing contract-net and negotiation algorithms whit which we hope to demonstrate that this can improve the overall functionality of a warehouse management system by comparing it against a more standard method such as random storage and controlling different aspects such as quantity of products arriving, number of lifters, product types, and utilizing different settings like arrival and consumption rate, storage method among other.

The agents in this enviroment are:

-Boxes: this agents represent the product boxes that are stores in a warehouse, they can move or be moved on the different areas of the enviroment from arrival to storage and from storgae to consumption area, thay can have different product type and priority.
-Lifters: The main function of this agents is to move the box agents from one area to another.

Agentsets
-Storage: represent the storage spaces that a box can occupy in the enviroment.
-Paths: represent the patches where the lifters can move trough.
-Consum: represnt the final stage area where the boxes can be conusmed posibly acording to there priority and type. 

Helper agentsets
-Assigned: represent the boxes that have already being allocated.
-Unassigned: represent the boxes that are ready for storage assignation.
-Unoccupied: represnt the patches that can hold a box.
-Boxes-with-type: represent the boxes that have the same type as the next order.
-Stored: represent the boxes that are already in the storage area.
-Free: represnt the available patches in the consuption-area.

The cooperation between agents

The negotiation


HOW IT WORKS
------------
As new boxes arrive they will signal they need to be stored, boxes will apear in arrival area in a determined number and in a specified time rate.
Lifters will then move the boxes from arrival area to available space in storage area according to the settings of the model this is priority, storage method, distance, etc. They will sit in this space untill required in consumption. Once required the lifters will move the boxes from storage to consumption.
There will be different consumption areas depending on the settings in  which boxes will be consumed (die) acording to priority, product type or consumption method in a given rate.    


HOW TO USE IT
-------------
The model has the following controls on the interface.

Settings:

Initialize the model by pressing SETUP, and press GO to run it.

Buttons:
SETUP - generates a new storage grid based on the current GRID-SIZE-X and GRID-SIZE-Y initial-boxes number of initial boxes, N-lifters number of lifters and conusmption areas. This also clears all the plots. 
GO - runs the simulation indefinitely.

Choosers:
STORAGE-METHOD - Allows you to choose between different storage methods:
                 CN-ARRIVAL.- CN with a simple criterion: Select the box with the highest priority, and this box in turn selects the storage space closest to consumption area.
                 CN-COMBINED.- Similar to CN-ARRIVAL, but selects n boxes with the highest priority.
		 RANDOM.- Stores the boxes randomly in any available space in the storage area.
		 NEAREST.- Stores the boxes in the available space closest to any stored boxed.
		 ARRIVAL.- Stores the boxes in the nearest available space from arrival.
		 CLASSIFIED.- Stores the boxes in the nearest available space to another stored box of same charateristic.
CONSUMPTION-METHOD - Allows you to choose between different methods to select the next box to move to the shipping or consumption area:
                     RANDOM.- Selects the next box randomly.
                     CN-CONSUMPTION.- Selects the box with the highest priority. The box in turn selects the conumption space based on product type and distance.
		     CN-COMBINED.- Similar to CN-CONSUMPTION, but selects the n boxes with the highest priority.
LIFTER-CRITERIA - Allows you to choose between different criteria to select a lifter for the task of moving a box:
		  CLOSEST.- Select the closest to the box.
		  RANDOM.- Select a lifter at random.
		  WORKLOAD.- Select the lifter with the lower number of tasks pending.

Sliders:
GRID-SIZE-X - sets the number of horizontal storage spaces there are (you must press the SETUP button to see the change) 
GRID-SIZE-Y - sets the number of vertical storage spaces there are (you must press the SETUP button to see the change) 
CONSUPMTION-AREAS - sets the number of consumption areas there are (you must press the SETUP button to see the change)
INITIAL-BOXES - sets the number of boxes in the begging of the model (you must press the SETUP button to see the change)
No-OF-LIFTERS - sets the number of lifters ther are (you must press the SETUP button to see the change)
ARRIVAL-RATE - controls the rate in wich new boxes arrive this is the ticks it takes for new boxes to appear.
CONSUMPTION-RATE - controls the rate in wich the boxes are consume this is the in how many tick boxes are consumed (die).
PRIORITY-SHIFT - controls the preferd priority of the boxes to be consume.

Switches:
START-AT-STORAGE? - toggles the initial area of boxes, this is if if there is initial inventory at storage area or start from empty storage, no initial inventory.
LIFTERS_AVAILABLE? - toggles wheter thera are lifters in the enviroment to move the boxes or not and boxes move by themselfs.

Inputs:
ARRIVAL-QUANTITY - allows you to enter the number of boxes you want to arrive.

Monitors:
ARRIVE - shows the number of boxes in arrival area.
STORED - shows the number of boxes in storage.
ON-CONSUMPTION - shows the number of boxes in cosumption.
%-STORAGE - shows the percentage of storage occupied.
DISPLACEMENT - shows the total distance covered by all the lifters.

Plots:
TOTALS - displays the number of boxes in each area trough time.
UTILITY - displays the utitlity of the current setting trough time.


THINGS TO NOTICE
----------------
- Changing the values of different controls (see Things to Try), changes the behavior like follows:
  - Boxes can be stored with different arrangements, some closer to the shipping area, arrival area, or just close to boxes with certain characteristics.
  - Lifter agents task allocation changes how much work each lifter has. Sometimes, the work load will be poorly balanced, but with other control values, the work load will be more even. (See Things to Try).
  - See how the utility changes over time, and how fast it grows with different configurations.


THINGS TO TRY
-------------
- Be sure to try different storage and consumption methods and see how the the simulation behavior changes.
- Changing the lifter criteria you can see how the lifter agents change behavior. In some cases, tasks allocation will be uneven, but with the "workload" option all the
lifters should be busy most of the time.
- Be sure to use the priority-shift slider and see how the boxes accomodation changes. This will increase the demand of certain product types. 

EXTENDING THE MODEL
-------------------
Some validation is required with certain settings in order to prevent the model from exiting unnespectenly like when the storage reaches maximum occupancy and when implementing negotiation some times the task list of the lifters dosent get updated to exclude task allready done by other agents.


CREDITS AND REFERENCES
----------------------
This model was programmed by Jorge Candelaria 787542 and Ulises Chavez 538968, as an assignment for the MultiAgent Systems course.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
0
Rectangle -7500403 true true 151 225 180 285
Rectangle -7500403 true true 47 225 75 285
Rectangle -7500403 true true 15 75 210 225
Circle -7500403 true true 135 75 150
Circle -16777216 true false 165 76 116

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 4.1.3
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 1.0 0.0
0.0 1 1.0 0.0
0.2 0 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
