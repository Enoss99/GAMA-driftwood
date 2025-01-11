/**
* Name: Driftwood project
* Author: chapu
* 
*/



model Driftwood
global {	
	int env_width <- 100;  
	int env_height <- 100; 
	// day-night cycle
	float current_time <- 0.0;         // time of day (0-24)
	float time_steps_per_hour <- 15.0; 
	float time_progress_rate <- 0.005; 
	float cycle_length <- time_steps_per_hour * 24; 
	float evening_start <- 19.0;       
	float morning_end <- 8.0;  
	// fixed boundaries
	int ocean_width <- int(env_width * 0.18); 
	int shore_start <- int(env_width * 0.60); 
	// terrain height
	float max_shore_height <- 5.0;       
	float water_level <- 0.0;           
	float shore_slope <- max_shore_height / (env_width - ocean_width); 
    // tide parameters
	float current_tide <- 0.2;    
	float low_tide <- 0.15;       
	float high_tide <- 1.0;       
	float tide_rate <- 0.0005;    
	float base_tide <- 0.15;
	// wood
	int starting_wood_count <- 20;   
	float wood_generation_rate <- 0.02; 
	// Spatial optimization
	float spatial_step <- 1.0;      						
	// wave
	float sim_time <- 0.0;        
	float baseline_wave <- 1.0;
	float wave_height <- 1.0;     
	float wave_rate <- 0.5;       
	float wave_flow <- 1.0;    
	// ex1
	int collector_count <- 5;         
	float minimum_greed <- 0.3;      
	float maximum_greed <- 0.8;       
	float collector_view_angle <- 100.0; 
	float collector_sight_range <- 10.0; 
	float base_steal_probability <- 0.1;  
	float steal_probability_increase <- 0.01; 
	float maximum_steal_probability <- 0.2; 
    float system_stability <- 0.0 update: calculate_system_stability();
    // ex2
    // authority parameters
    bool enable_authority <- true;                          
    int num_authorities <- 2;               	
    float authority_fov <- 120.0;                          
    float authority_view_distance <- 15.0;                  
    float authority_speed <- 1.5;                          	    
    float patrol_interval <- 100.0;                         
    int fine_amount <- 3;                              		   
    // patrol points
    list<point> patrol_points <- [];                       	
    int num_patrol_points <- 5;                            
    string authority_type <- "patrol" among: ["patrol", "stationary"];
    // pursuit mode
    float thief_detection_radius <- 20.0;          			
    bool authority_actively_pursues <- true;       			
	int active_pursuits <- 0 update: Authority count (each.is_pursuing);
	bool enable_cameras <- true;							
	int num_cameras <- 2;    								
    float camera_detection_radius <- 20.0;
	int total_catches <- 0;  								
    // ex3
    // grp
    int current_group_id <- 0 
    			update: empty(Collector where each.is_group_leader) ? 0 : max(Collector where each.is_group_leader collect each.group_id ) + 1;
    int min_group_size <- 2;                                
    int max_group_size <- 4;                                
    float group_formation_chance <- 0.3;                    
    float group_breakup_chance <- 0.1;                      
    float group_cohesion_radius <- 5.0;                     
    float cooperation_bonus <- 0.2;                         
    // for analysis
    map<int, float> group_efficiency <- [];         		
    map<int, int> group_total_collected <- [];      		
    float system_perturbation <- 0.0;              			
    bool apply_perturbation <- false;              			
    int perturbation_interval <- 500;              			
    float perturbation_strength <- 0.2;
    int perturbation_recovery_time <- 500;    				
    bool perturbation_active <- false;
    int perturbation_start_time <- 0;
    // grp effectiveness
    float avg_group_collection_rate <- 0.0 update: empty(group_efficiency.values) ? 0.0 : mean(group_efficiency.values);
    float solo_vs_group_efficiency <- 0.0 update: calculate_solo_vs_group_efficiency();
    int cleanup_interval <- 100;  							
	int win_value <- 50;									// Required number for pile to win
	bool simulation_ended <- false;
	
	init {
	    create Driftwood number: starting_wood_count {
        	float spawn_x <- float(rnd(ocean_width - 5.0, ocean_width));
        	float spawn_y <- rnd(0.0, env_height - 1.0);
            location <- {spawn_x, spawn_y};          
        }
        create Collector number: collector_count;
        patrol_points <- [];
        int patrol_margin <- 10;
        float beach_section <- (env_height - 2 * patrol_margin) / num_patrol_points;
        
        loop i from: 0 to: num_patrol_points - 1 {
            float y_pos <- patrol_margin + (i * beach_section) + rnd(-5.0, 5.0);
            point patrol_point <- {
                rnd(shore_start + 5, env_width - 5),
                min(env_height - patrol_margin, max(patrol_margin, y_pos))
            };
            patrol_points <- patrol_points + patrol_point;
        }
        if (enable_authority) {
            create Authority number: num_authorities;
	        if (enable_cameras) {
	            create SecurityCamera number: num_cameras {
	                location <- {
	                    rnd(shore_start + 5, env_width - 5),
	                    rnd(5, env_height - 5)
	                };
	            }
	        }
        }
	}
    reflex update_time {
    	sim_time <- sim_time + wave_flow;
    }
    // Day-Night
    reflex update_day_time {
	    current_time <- current_time + time_progress_rate;
	    if (current_time >= 24.0) {
	        current_time <- 0.0;
	    }
	}
reflex update_tide {
    // rising tide: 0-6, 12-18
    if ((current_time >= 0.0 and current_time < 6.0) or (current_time >= 12.0 and current_time < 18.0)) {
        current_tide <- current_tide + tide_rate;
        if (current_tide > base_tide + high_tide) {
            current_tide <- base_tide + high_tide;
        }
    } else { 
        // falling tide: 6-12, 18-24
        current_tide <- current_tide - tide_rate;
        if (current_tide < base_tide + low_tide) {
            current_tide <- base_tide + low_tide;
        }
    }
}
    reflex generate_wood {
        if (flip(wood_generation_rate)) {
            create Driftwood number: 1 {
                float spawn_x <- float(rnd(ocean_width - 5.0, ocean_width));
                float spawn_y <- rnd(0.0, env_height - 1.0);
                location <- {spawn_x, spawn_y};
            }
        }
    }
    float calculate_system_stability {
	    float theft_rate <- empty(WoodPile) ? 0 : mean(WoodPile collect each.times_stolen_from);
	    float catch_effectiveness <- total_catches / max(1, sum(Collector collect each.successful_steals));
	    return (1.0 - (theft_rate / 100)) * (catch_effectiveness) with_precision 2;
	}
    float calculate_solo_vs_group_efficiency {
        list<Collector> solo_collectors <- Collector where (!each.in_group);
        list<Collector> grouped_collectors <- Collector where (each.in_group);
	    float solo_efficiency <- empty(solo_collectors) ? 0.0 : 
	        mean(solo_collectors collect (
	        	each.wood_collected_count / max(1, cycle)
	        ));
	    float grouped_efficiency <- empty(grouped_collectors) ? 0.0 : 
	        mean(grouped_collectors collect (
	        	each.wood_collected_count / max(1, cycle)
	        ));
	    if (empty(grouped_collectors) or grouped_efficiency = 0.0) {
	        return 0.0;
	    } else {
	        return (grouped_efficiency - solo_efficiency) / grouped_efficiency;
	    }
    }
    reflex check_end_condition {
	    if (simulation_ended) { return; }
	    list<WoodPile> winning_piles <- WoodPile where (
	        each != nil and                				   	
    		!dead(each) and                 				
	        each.pile_value >= win_value and         		
	        each.wood_pieces != nil and       				
	        !dead(each.wood_pieces)           				
	    );
	    if (!empty(winning_piles)) {
	        simulation_ended <- true;
	        do pause;
	        write "\nSIMULATION END";
	        write "Time: " + current_time;
	        write "Winning pile:";
	        loop pile over: winning_piles {
	            write "-Owner: " + pile.owner + " | Value: " + pile.pile_value;
	        }
	    }

	}
    
}
// environment - beach cells
grid Beach_Cell width: env_width height: env_height {
    rgb color <- rgb(194, 178, 128);
    float height <- 0.0;
    float wave_value <- 0.0;
    bool was_underwater <- false;
    rgb base_sand_color <- rgb(194, 178, 128);  
    rgb sea_color <- rgb(65,107,223);          
    rgb shallow_water_color <- rgb(92,181,225);
    float get_water_depth {
        if (	color = sea_color or color = shallow_water_color
        ) {
        	float base_water_level <- current_tide * max_shore_height; 	
        	float depth <- base_water_level - height; 
            return max(0.0, depth);							
        }
        return 0.0;
    }
    init {
        if (grid_x < ocean_width) {
            height <- water_level;
        } else {
            float distance_from_sea <- float(grid_x - water_level);
            height <- distance_from_sea * shore_slope;
        }
        float y_sin <- sin(wave_rate * float(grid_y));
        float sec_y_sin <- sin(0.05 * float(grid_y));
        wave_value <- baseline_wave + (wave_height * y_sin) + sec_y_sin;
        float adjusted_sea_width <- ocean_width + wave_value;
        if (grid_x < adjusted_sea_width) {
            color <- sea_color;
            was_underwater <- true;
        }
    }
    
    reflex update_cell when: every(2 #cycles) {
        if (grid_x > shore_start and !was_underwater) { return; }
	    float y_factor <- wave_rate * float(grid_y) + sim_time;
	    wave_value <- baseline_wave + wave_flow * sin(y_factor) + sin(0.05 * float(grid_y) + sim_time * 0.5);
	    float adjusted_sea_width <- ocean_width + wave_value;
	    float adjusted_beach_start <- shore_start + wave_value;
	    bool is_underwater <- false;
	    if (grid_x < adjusted_sea_width) {
	        color <- sea_color;
	        is_underwater <- true;
	    } else {
	        float tide_zone <- adjusted_sea_width + (current_tide * (adjusted_beach_start - adjusted_sea_width));
	        
	        if (grid_x < tide_zone) {
	            color <- shallow_water_color;
	            is_underwater <- true;
	        } else {
	                color <- base_sand_color;
	        }
	    }
	    
	    was_underwater <- is_underwater;
	}
}
// ------------------------------------------------------------------------------------------
// driftwood species
species Driftwood {
    string size_category;
    float width;          
    float height;         
    bool is_collected <- false; 
    bool in_pile <- false;     
    int value;                
    rgb wood_color <- rgb(186,140,99);
    init {
        size_category <- one_of(["small", "medium", "large"]);
        switch size_category { 
            match "small" { 
                width <- 0.8; 
                value <- 1;
            } 
            match "medium" { 
                width <- 1.2; 
                value <- 3;
            } 
            match "large" { 
                width <- 1.6; 
                value <- 5;
            } 
        }
    }
aspect default {
    if (!is_collected) {
        draw square(width ) color: wood_color ;
        draw square(width + 0.1) color: wood_color ;
    } else if (in_pile) {
        draw square(width) color: wood_color ;
        draw square(width - 0.1) color: wood_color ;
    }
}
	reflex move when: !is_collected and !in_pile {
	    Beach_Cell current_cell <- Beach_Cell(location);
	    if (current_cell != nil) {
	        if (current_cell.color = current_cell.sea_color or current_cell.color = current_cell.shallow_water_color) {
	            bool is_tide_rising <- (current_time >= 0.0 and current_time < 6.0) or (current_time >= 12.0 and current_time < 18.0);	            
	            float tide_movement <- 0.0;
	            float size_factor;	            	           
	            switch size_category { 
	                match "small" { 
	                    size_factor <- is_tide_rising ? 60.0 : 30.0; 
	                } 
	                match "medium" { 
	                    size_factor <- is_tide_rising ? 50.0 : 20.0;
	                } 
	                match "large" { 
	                    size_factor <- is_tide_rising ? 40.0 : 10.0;
	                } 
	            }
	            tide_movement <- is_tide_rising 
	                ? tide_rate * size_factor
	                : -tide_rate * size_factor; 
	            float wave_factor <- size_category = "small" ? 0.020 : (size_category = "medium" ? 0.015 : 0.010);
	            float wave_influence <- sin(sim_time + location.y * wave_rate) * wave_factor;
	            location <- location + {tide_movement + wave_influence, 0};
	        }
	    }
	}
}
// ------------------------------------------------------------------------------------------
// collector species
species Collector skills: [moving] {
    bool has_pile <- false;
    point pile_location <- nil; 
    rgb color <- #black;        
    Driftwood targeted_wood <- nil; 
    list<Driftwood> carried_wood <- []; 
    int current_carried_value <- 0;    
    int max_carrying_value <- 15;      
    float greed <- rnd(minimum_greed, maximum_greed); 
    float fov <- collector_view_angle;         
    float view_distance <- collector_sight_range; 
    map<point,bool> fov_cache;                
    int cache_duration <- 20;                  
    int last_cache_update <- 0;
    bool is_stealing <- false;         
    WoodPile target_pile <- nil;       
    float steal_chance <- base_steal_probability; 
    int successful_steals <- 0;        
    float start_stealing_time <- time update: is_stealing ? start_stealing_time : time;
    float stealing_timeout <- 100.0;   
    // grp
    int group_id <- -1;         							
    bool in_group <- false;
    list<Collector> group_members <- [];
    Collector group_leader <- nil;
    rgb group_color <- nil;
    // grp behavior
    float group_role_chance <- 0.5;                         
    bool is_group_leader <- false;
    point group_gathering_point <- nil;
    
	int wood_collected_count <- 0;              			
    float collection_efficiency <- 0.0 update: cycle = 0 ? 0.0 : wood_collected_count / cycle;
    init {
		location <- {rnd(shore_start, env_width - 1), rnd(0, env_height - 1)};
	    pile_location <- {
	        rnd(shore_start + 5, env_width - 5),
	        rnd(5, env_height - 5)
	    };
	}
    reflex update_speed {
	    speed <- 2.0;
	    if (!empty(carried_wood)) {
	        float reduction_factor <- max(0.2, 1.0 - (current_carried_value / max_carrying_value));
	        speed <- speed * reduction_factor; 
	    }
	    Beach_Cell current_cell <- Beach_Cell(location);
	}
    reflex wander when: (targeted_wood = nil) and empty(carried_wood) {
        do wander amplitude: 75.0 speed: speed / 4.0;  			
    }
	bool is_in_fov(point target_loc) {
	    if (target_loc = nil) { return false; }
	    float distance <- location distance_to target_loc;
	    if (distance > view_distance) { 
	        fov_cache[target_loc] <- false;
	        last_cache_update <- cycle;
	        return false; 
	    }
	    if (fov_cache contains_key target_loc and cycle - last_cache_update < cache_duration) {
	        return fov_cache[target_loc];
	    }
	    float dx <- target_loc.x - location.x;
	    float dy <- target_loc.y - location.y;
	    float angle_to_target <- atan2(dy, dx) * (180 / #pi);
	    float normalized_heading <- float(heading mod 360);
	    if (normalized_heading < 0) { normalized_heading <- normalized_heading + 360; }
	    angle_to_target <- float(angle_to_target mod 360);
	    if (angle_to_target < 0) { angle_to_target <- angle_to_target + 360; }
	    float angle_diff <- abs(normalized_heading - angle_to_target);
	    if (angle_diff > 180) { angle_diff <- 360 - angle_diff; }
	    bool is_visible <- angle_diff <= fov / 2;
	    fov_cache[target_loc] <- is_visible;
	    last_cache_update <- cycle;
	    
	    return is_visible;
	}
    reflex clear_fov_cache when: every(cache_duration) {
        fov_cache <- [];
    }
    list<Driftwood> get_visible_wood(list<Driftwood> wood_pieces) {
        return wood_pieces where (is_in_fov(each.location));
    }
	reflex target_wood when: empty(carried_wood) and targeted_wood = nil and every(3 #cycles) {
	    list<Driftwood> nearby_wood <- Driftwood at_distance view_distance 
	        where (!each.is_collected and !each.in_pile);
	    if (!empty(nearby_wood)) {
	        targeted_wood <- nearby_wood closest_to self; 
	    }
	}
	reflex check_targeted_wood when: targeted_wood != nil {
	    if (targeted_wood.is_collected or 
	        (current_carried_value + targeted_wood.value > max_carrying_value)) {
	        targeted_wood <- nil;
	        list<Driftwood> available_wood <- Driftwood 
	            where (
	                !each.is_collected 
	            and 
	                !each.in_pile
	            and
	                current_carried_value + each.value <= max_carrying_value
	            );
	        
	        if (!empty(available_wood)) {
	            targeted_wood <- available_wood closest_to self;
	        }
	    }
	}
    reflex move_to_wood when: targeted_wood != nil {
        if (location distance_to targeted_wood > 50.0) {
            targeted_wood <- nil;
            return;
        }
        if (speed <= 0) {
            speed <- rnd(0.0, 8.0);
        }
        if (targeted_wood.is_collected) {
            targeted_wood <- nil;
            return;
        }
        if (dead(targeted_wood) or targeted_wood = nil) {
	        targeted_wood <- nil;
	        return;
	    }
        if (location distance_to targeted_wood > spatial_step) {
            do goto target: targeted_wood speed: speed / 3.6;
        }
        if (location distance_to targeted_wood < 1.0) {

            carried_wood <- carried_wood + targeted_wood;
            current_carried_value <- current_carried_value + targeted_wood.value;
            targeted_wood.is_collected <- true;
            if (!has_pile) {
                pile_location <- {
                        rnd(shore_start + 5, env_width - 5),
                        rnd(5, env_height - 5)
                };
                has_pile <- true;
            }
            bool continue_collecting <- flip(greed * (1 - (current_carried_value / max_carrying_value)));
            
            if (!continue_collecting) {
                targeted_wood <- nil;
                return;
            }
            list<Driftwood> available_wood <- Driftwood 
                where (
                    !each.is_collected 
                and 
                    !each.in_pile
                and
                    current_carried_value + each.value <= max_carrying_value
                );
                
            if (!empty(available_wood)) {
                targeted_wood <- available_wood closest_to self;
            } else {
                targeted_wood <- nil;
            }
        }
    }
	reflex return_to_pile when: (!empty(carried_wood) and (
	        current_carried_value = max_carrying_value or
	        targeted_wood = nil                             
	)) {
	    if (pile_location = nil) {
	        pile_location <- {
	            rnd(shore_start + 5, env_width - 5),
	            rnd(5, env_height - 5)
	        };
	    }
	    
	    do goto target: pile_location speed: speed / 3.6;
	
	    if (location distance_to pile_location < 1.0) {
	        WoodPile existing_pile <- first(WoodPile where (
	            each.owner = self and 
	            each.location distance_to pile_location < 1.0
	        ));
	        
	        if (existing_pile = nil) {
	            create WoodPile {
	                location <- myself.pile_location;
	                owner <- myself;
	                wood_pieces <- first(myself.carried_wood);
	                ask first(myself.carried_wood) {
	                    location <- myself.location;
	                    in_pile <- true;
	                }
	            }
	            carried_wood <- carried_wood - first(carried_wood);
	        }
	        loop wood over: carried_wood {
	            ask wood {
	                location <- myself.pile_location;
	                in_pile <- true;
	            }
	        }
	        wood_collected_count <- wood_collected_count + length(carried_wood);
	        // ex3
	        if (in_group and group_id >= 0) {
	            ask world {
	                if (empty(group_total_collected) or !(group_total_collected.keys contains myself.group_id)) {
	                    group_total_collected[myself.group_id] <- 0;
	                }
	                group_total_collected[myself.group_id] <- group_total_collected[myself.group_id] + length(myself.carried_wood);
	                list<Collector> current_group_members <- Collector where (each.group_id = myself.group_id);
	                if (!empty(current_group_members)) {
	                    group_efficiency[myself.group_id] <- mean(current_group_members collect each.collection_efficiency);
	                }
	            }
	        }
	        carried_wood <- [];
	        current_carried_value <- 0;
	        targeted_wood <- nil;
	       
	        has_pile <- true;
	    }
	}
    bool is_pile_observed(WoodPile pile) {
        Collector owner <- pile.owner;
        if (owner = nil) { return false; }
        return owner.is_in_fov(pile.location) and owner.is_in_fov(self.location) and 
               (owner.location distance_to pile.location <= owner.view_distance);
    }
    list<WoodPile> get_stealable_piles {
        return WoodPile where (
            each.owner != self and           				
            !is_pile_observed(each) and      				
            each.pile_value > 0 and          				
            is_in_fov(each.location)         				
        );
    }
    //ex1
    reflex consider_stealing when: empty(carried_wood) and !is_stealing and every(5 #cycles) {
	    if (flip(steal_chance)) {
	        list<WoodPile> potential_targets <-get_stealable_piles();
	        
	        if (!empty(potential_targets)) {
	            target_pile <- potential_targets with_max_of(each.pile_value);
	            is_stealing <- true;
	        }
	    }
	}

	reflex move_to_steal when: is_stealing and target_pile != nil {
        if (time - start_stealing_time > stealing_timeout) {
            is_stealing <- false;
            target_pile <- nil;
            return;
        }
        if (dead(target_pile) or target_pile = nil or target_pile.pile_value <= 0) {
            is_stealing <- false;
            target_pile <- nil;
            return;
        }
        if (target_pile.owner != nil and !dead(target_pile.owner) and 
            target_pile.owner.is_in_fov(target_pile.location)) {
            is_stealing <- false;
            target_pile <- nil;
            return;
        }
        do goto target: target_pile.location speed: speed / 3.6;
        if (location distance_to target_pile.location < 1.0) {
            list<Driftwood> stealable_wood <- Driftwood at_distance 1.0
                where (each.in_pile and !dead(each) and 
                    current_carried_value + each.value <= max_carrying_value);
            if (!empty(stealable_wood)) {
                Driftwood stolen_wood <- stealable_wood first_with (
                    !dead(each) and current_carried_value + each.value <= max_carrying_value
                );
                if (stolen_wood != nil) {
                    stolen_wood.in_pile <- false;
                    carried_wood <- carried_wood + stolen_wood;
                    current_carried_value <- current_carried_value + stolen_wood.value;
                    steal_chance <- min(maximum_steal_probability, base_steal_probability + steal_probability_increase);
                    successful_steals <- successful_steals + 1;
                }
            }
            is_stealing <- false;
            target_pile <- nil;
        }
    }
    // grp formation
    reflex consider_forming_group 
    			when: !in_group 
    			and flip(group_formation_chance) 
    			and every(50 #cycles) 
    {
        list<Collector> potential_members <- Collector at_distance view_distance where (!each.in_group);
        if (length(potential_members) >= min_group_size - 1) {
            list<Collector> new_group <- [self];
            is_group_leader <- true;
            group_color <- rgb(rnd(0,255), rnd(0,255), rnd(0,255));
            group_id <- current_group_id;
            loop times: min(max_group_size - 1, length(potential_members)) {
                Collector new_member <- one_of(potential_members where (!each.in_group));
                if (new_member != nil) {
                    new_group <- new_group + new_member;
                    potential_members <- potential_members - new_member;
                }
            }
            ask new_group {
                in_group <- true;
                group_members <- new_group;
                group_leader <- myself;
                self.group_color <- myself.group_color;
                self.group_id <- myself.group_id;
                max_carrying_value <- int(max_carrying_value * (1 + cooperation_bonus));
            }
            write "Group " + group_id + " formed grp with " + length(new_group) ;
        }
    }
    reflex maintain_group_cohesion when: in_group and !is_group_leader {
        if (group_leader != nil and !dead(group_leader)) {
            if (location distance_to group_leader.location > group_cohesion_radius) {
                do goto target: group_leader.location speed: speed / 3.6;
            }
        } else {
            do leave_group;
        }
    }
    reflex lead_group when: is_group_leader {
        if (empty(group_members where (each != self))) {
            do leave_group;
        } else {
            list<Driftwood> visible_wood <- get_visible_wood(Driftwood where (!each.is_collected));
            if (!empty(visible_wood) and !empty(group_members)) {
                loop member over: group_members where (each != self) {
                    if (member.targeted_wood = nil) {
                        member.targeted_wood <- one_of(visible_wood);
                    }
                }
            }
        }
    }
    action leave_group {
        if (is_group_leader) {
            ask group_members where (each != self) {
                in_group <- false;
                group_members <- [];
                group_leader <- nil;
                group_color <- nil;
                group_id <- -1;
                max_carrying_value <- int(max_carrying_value / (1 + cooperation_bonus));
            }
        }
        in_group <- false;
        group_members <- [];
        group_leader <- nil;
        is_group_leader <- false;
        group_color <- nil;
        group_id <- -1;
        max_carrying_value <- int(max_carrying_value / (1 + cooperation_bonus));
    }
    reflex consider_group_breakup when: in_group and flip(group_breakup_chance) and every(100 #cycles) {
        do leave_group;
    }
    reflex adapt_group_size when: is_group_leader and every(100 #cycles) {
	    float current_efficiency <- collection_efficiency;
	    if (current_efficiency > mean(Collector where (!each.in_group) collect each.collection_efficiency)) {
	        int potential_recruits <- length(Collector where (!each.in_group));
	        if (potential_recruits > 0 and length(group_members) < max_group_size) {
	            Collector new_member <- one_of(Collector where (!each.in_group));
	            if (new_member != nil) {
	                ask new_member {
	                    in_group <- true;
	                    group_members <- myself.group_members + self;
	                    group_leader <- myself;
	                    group_color <- myself.group_color;
	                    group_id <- myself.group_id;
	                    max_carrying_value <- int(max_carrying_value * (1 + cooperation_bonus));
	                }
	                group_members <- group_members + new_member;
	            }
	        }
	    }
	    else if (length(group_members) > min_group_size) {
	        Collector member_to_remove <- one_of(group_members where (each != self));
	        if (member_to_remove != nil) {
	            ask member_to_remove {
	                do leave_group;
	            }
	        }
	    }
	}
    aspect default {
	    draw circle(0.5) color: color;
	    if (!empty(carried_wood)) {
	        draw triangle(2) color: #brown rotate: heading + 90;
	    }
	    if (has_pile) {
	        draw triangle(1) color: #blue at: {location.x, location.y + 1};
	    }
	    point p1 <- {
	        location.x + view_distance * cos(heading - fov / 2),
	        location.y + view_distance * sin(heading - fov / 2)
	    };
	    point p2 <- {
	        location.x + view_distance * cos(heading + fov / 2),
	        location.y + view_distance * sin(heading + fov / 2)
	    };
	    draw polyline([location, p1]) color: rgb(200,200,200,200);
	    draw polyline([location, p2]) color: rgb(200,200,200,200);
	    
	    list<point> fan_vertices <- [location];
	    int segments <- 20;
	    loop i from: 0 to: segments {
	        float ratio <- i / segments;
	        float current_angle <- heading - fov / 2 + ratio * fov;
	        point vertex <- {
	            location.x + view_distance * cos(current_angle),
	            location.y + view_distance * sin(current_angle)
	        };
	        fan_vertices <- fan_vertices + vertex;
	    }
	    draw polygon(fan_vertices) color: rgb(200,100,100,50);
        Beach_Cell current_cell <- Beach_Cell(location);
        string group_info <- "";
        if in_group {
            if is_group_leader {
                group_info <- " [L" + group_id + "]";
            } else {
                group_info <- " [M" + group_id + "]";
            }
        }
	    // display collector info above position
	    draw string("")
	        + " [" + current_carried_value + "/" + max_carrying_value + "]"
	        + " steal:" + (int(steal_chance * 100)) + "%"
	       
	        color: #black size: 8 at: {location.x, location.y - 2};
    }
}

// ------------------------------------------------------------------------------------------
// woodpile 
species WoodPile {
    Collector owner;
    Driftwood wood_pieces;
    bool has_marker <- true;
    int pile_value <- 0;
    float creation_time <- time;              				
    int times_stolen_from <- 0;             				
    float last_theft_time <- -1.0;         				  
    float stability_score <- 1.0;
    reflex update_pile_value {
	    if (location = nil or dead(self)) { return; }
	    list<Driftwood> woods_in_pile <- Driftwood at_distance 1.0
            where (each.in_pile and each.is_collected);
        pile_value <- sum(woods_in_pile collect (each.value));
	}
    reflex update_theft_tracking when: every(10 #cycles) {
        if (dead(self) or location = nil) { return; }
        int current_wood_count <- length(Driftwood at_distance 1.0 
            where (each.in_pile and !dead(each)));
        if (current_wood_count < pile_value) {
            if (time - last_theft_time > 20.0) {
                times_stolen_from <- times_stolen_from + 1;
                last_theft_time <- time;
            }
            pile_value <- current_wood_count;
        }
    }
    aspect default {
	    if (has_marker) {
	        // draw pile marker (two stones)
	        draw circle(0.5) color: #blue at: {location.x - 0.5, location.y}; 
	    }
	}
}
// ------------------------------------------------------------------------------------------
// authority species
species Authority skills: [moving] {
    point current_patrol_point <- nil;
    list<Collector> observed_thieves <- [];
    rgb color <- #green;
    bool is_pursuing <- false;
    Collector pursuit_target <- nil;
    
    init {
        location <- one_of(patrol_points);
        current_patrol_point <- one_of(patrol_points);
    }
    bool is_in_authority_fov(point target_loc) {
        if (target_loc = nil) { return false; }
        float distance <- location distance_to target_loc;
        if (distance > authority_view_distance) { return false; }
        float dx <- target_loc.x - location.x;
        float dy <- target_loc.y - location.y;
        float angle_to_target <- atan2(dy, dx) * (180/#pi);
        float normalized_heading <- float(heading mod 360);
        if (normalized_heading < 0) { normalized_heading <- normalized_heading + 360; }
        angle_to_target <- float(angle_to_target mod 360);
        if (angle_to_target < 0) { angle_to_target <- angle_to_target + 360; }
        float angle_diff <- abs(normalized_heading - angle_to_target);
        if (angle_diff > 180) { angle_diff <- 360 - angle_diff; }
        return angle_diff <= authority_fov/2;
    }
    reflex observe_collectors {
        observed_thieves <- [];
        list<Collector> nearby_collectors <- Collector at_distance authority_view_distance;
        
        loop collector over: nearby_collectors {
            if (collector != nil and !dead(collector)) {
                if (is_in_authority_fov(collector.location)) {
                    if (collector.is_stealing) {
                        observed_thieves <- observed_thieves + collector;
                        pursuit_target <- collector;
                        is_pursuing <- true;
                    }
                }
            }
        }
    }
    reflex patrol when: !is_pursuing and current_patrol_point != nil {
        switch authority_type {								
	        match "patrol" {
	            do goto target: current_patrol_point speed: authority_speed;
	            if (location distance_to current_patrol_point < 1.0) {
	                if (!empty(WoodPile)) {
	                    list<point> prioritized_points <- patrol_points sort_by (each distance_to (WoodPile closest_to self).location);
	                    current_patrol_point <- prioritized_points first_with (each != location);
	                } else {
	                    current_patrol_point <- one_of(patrol_points - current_patrol_point);
	                }
	            }
	        }
	        match "stationary" {
	            heading <- heading + 2.0;
	        }
	    }
    }
    reflex change_patrol when: every(patrol_interval) {
        current_patrol_point <- one_of(patrol_points - current_patrol_point);
    }
    reflex detect_thieves {
        list<Collector> suspicious_collectors <- Collector at_distance thief_detection_radius;
        list<WoodPile> nearby_piles <- WoodPile at_distance thief_detection_radius;
        loop collector over: suspicious_collectors {
            if (collector.is_stealing) {
                write "-" + self+ " detected stealing behavior!";
                pursuit_target <- collector;
                is_pursuing <- true;
                break;
            }
            loop pile over: nearby_piles {
                if (pile.owner != collector and 
                    (collector.location distance_to pile.location) < 3.0) {
                    write "Authority detected suspicious behavior near pile " + pile.location+ "!";
                    pursuit_target <- collector;
                    is_pursuing <- true;
                    break;
                }
            }
        }
    }
    reflex pursue when: is_pursuing {
        if (pursuit_target = nil or dead(pursuit_target)) {
            is_pursuing <- false;
            pursuit_target <- nil;
            return;
        }
        float dist <- location distance_to pursuit_target;
        int authority_fine <- fine_amount;
        
        if (dist < 2.0) { 
            write "-" + self + " caught thief " + pursuit_target + " at location " + pursuit_target.location;
            ask pursuit_target {
                steal_chance <- max(0.0, steal_chance - (authority_fine * 0.01));
                is_stealing <- false;
                target_pile <- nil;
                color <- #red;
                if (has_pile) {
                    list<WoodPile> collector_piles <- WoodPile where (each.owner = self);
                    ask collector_piles {
                        int wood_to_remove <- min(authority_fine, pile_value);
                        list<Driftwood> nearby_wood <- Driftwood at_distance 1.0 where (each.in_pile);
                        loop times: wood_to_remove { 
                            if (!empty(nearby_wood)) {
                                ask first(nearby_wood) {
                                    do die;
                                }
                                nearby_wood <- nearby_wood - first(nearby_wood);
                            }
                        }
                        pile_value <- pile_value - wood_to_remove;
                    }
                }
            }
            ask world { total_catches <- total_catches + 1; }
            is_pursuing <- false;
            pursuit_target <- nil;
        } 
        else if (dist > thief_detection_radius * 1.5) { 
            is_pursuing <- false;
            pursuit_target <- nil;
        }
        else {  
            do goto target: pursuit_target speed: authority_speed * 1.5;
        }
    }
    aspect default {

        rgb authority_color <- authority_type = "patrol" ? #green : #green;
        draw circle(1.5) color: is_pursuing ? #red : color;
        list<point> fov_points <- [location];
        int segments <- 20;
        float start_angle <- heading - authority_fov/2;
        float angle_step <- authority_fov/segments;
        loop i from: 0 to: segments {
            float current_angle <- start_angle + angle_step * i;
            point vertex <- {
                location.x + authority_view_distance * cos(current_angle),
                location.y + authority_view_distance * sin(current_angle)
            };
            fov_points <- fov_points + vertex;
        }
        draw polygon(fov_points) color: is_pursuing ?  rgb(255,0,0,50) : rgb(0,200,0,50);
        draw circle(thief_detection_radius) color: rgb(0,0,255,10);
        if (is_pursuing and pursuit_target != nil) {
            draw line([location, pursuit_target.location]) color: #red;
        }
        point direction_point <- {
            location.x + 3 * cos(heading),
            location.y + 3 * sin(heading)
        };
        draw line([location, direction_point]) color: #black;
    }
    
}
// ------------------------------------------------------------------------------------------
// stationary patrol - 
species SecurityCamera {
    float detection_radius <- camera_detection_radius;
    float rotation <- 0.0;  								
    float rotation_speed <- 2.5;  							
    float view_angle <- 120.0;  
    reflex rotate {
        rotation <- rotation + rotation_speed;
        if (rotation >= 360.0) { rotation <- 0.0; }
    }
    reflex detect_thieves when: enable_cameras {
        list<Collector> detected <- Collector at_distance detection_radius;
        ask detected {
            if (self.is_stealing) {
            	write "-" + myself + " caught thief " + self + " at location " + location;
                self.steal_chance <- max(0.0, self.steal_chance - (fine_amount*0.01 - 0.01));
                self.is_stealing <- false;
                self.target_pile <- nil;
                self.color <- #red;
			    if (self.has_pile) {
                    list<WoodPile> collector_piles <- WoodPile where (each.owner = self);
                    ask collector_piles {
                        int wood_to_remove <- min(fine_amount, pile_value);
                        list<Driftwood> nearby_wood <- Driftwood at_distance 1.0 where (each.in_pile);
                        loop times: wood_to_remove { 
                            if (!empty(nearby_wood)) {
                                ask first(nearby_wood) {
                                    do die;
                                }
                                nearby_wood <- nearby_wood - first(nearby_wood);
                            }
                        }
                        pile_value <- pile_value - wood_to_remove;
                    }
                }
                ask world { total_catches <- total_catches + 1; }
            }
        }
    }
    
    aspect default {
        draw circle(1.0) color: #green;						
        draw triangle(2.0) color: #green rotate: rotation;
        list<point> fov_points <- [location];
        int segments <- 20;
        float start_angle <- rotation - view_angle/2;
        float angle_step <- view_angle/segments;
        loop i from: 0 to: segments {
            float current_angle <- start_angle + angle_step * i;
            point vertex <- {
                location.x + detection_radius * cos(current_angle),
                location.y + detection_radius * sin(current_angle)
            };
            fov_points <- fov_points + vertex;
        }
        draw polygon(fov_points) color: rgb(0,200,0,30); 
        draw circle(detection_radius) 						
        					color: rgb(0,200,0,30);
    }
}
    
   



// ------------------------------------------------------------------------------------------

experiment experience type: gui {

	parameter "wave height" var: wave_height min: 6.0 max: 6.0;
	parameter "wave baseline" var: baseline_wave min: 0.1 max:1.0;
	parameter "wave rate" var: wave_rate min: 0.1 max: 1.9;
	parameter "wave flow" var: wave_flow min: 0.1 max: 1.9;
	parameter "tide rate" var: tide_rate min: 0.0001 max: 0.0025;
	parameter "count of collectors" var: collector_count min: 2 max: 20;
	parameter "minimum greed" var: minimum_greed min: 0.0 max: 1.0;
	parameter "maximum greed" var: maximum_greed min: 0.0 max: 1.0;
	parameter "base steal chance" var: base_steal_probability min: 0.0 max: 0.5;
	parameter "max steal probability" var: maximum_steal_probability min: 0.1 max: 0.9;
	parameter "steal probability increase" var: steal_probability_increase min: 0.001 max: 0.05;
    parameter "Number of Authorities" var: num_authorities min: 1 max: 5;
    parameter "Authority View Distance" var: authority_view_distance min: 10.0 max: 30.0;
    parameter "Number of Cameras" var: num_cameras min: 1 max: 10;
    parameter "Camera Detection Radius" var: camera_detection_radius min: 10.0 max: 30.0;
    parameter "Min Group Size" var: min_group_size min: 2 max: 5;
    parameter "Max Group Size" var: max_group_size min: 3 max: 8;
    parameter "Group Formation Chance" var: group_formation_chance min: 0.1 max: 0.5;
    parameter "Group Breakup Chance" var: group_breakup_chance min: 0.05 max: 0.2;
    parameter "Cooperation Bonus" var: cooperation_bonus min: 0.1 max: 0.5;
    
    
    output {
        display main_display {
            grid Beach_Cell;
            species Driftwood;
            species Collector;
            species WoodPile;
            species Authority;
            species SecurityCamera;
	        graphics "display" {
			    int display_hours <- int(current_time);
			    int display_minutes <- int((current_time - display_hours) * 60);
			    string hours <- display_hours < 10 ? "0" + string(display_hours) : string(display_hours);
			    string minutes <- display_minutes < 10 ? "0" + string(display_minutes) : string(display_minutes);
			    draw "Time: " + hours + ":" + minutes at: {2, 5} color: #orange font: font("Default", 10, #bold);
			    // Height information for mouse hover
                point mouse_loc <- #user_location;
				    if (mouse_loc != nil) {
				        // Convert mouse location to grid coordinates
				        point grid_loc <- {int(mouse_loc.x * env_width / world.shape.width), 
				                          int(mouse_loc.y * env_height / world.shape.height)};
				        
				        // Check if the location is within grid bounds
				        if (grid_loc.x >= 0 and grid_loc.x < env_width and 
				            grid_loc.y >= 0 and grid_loc.y < env_height) {
				            
				            Beach_Cell cell <- Beach_Cell[int(grid_loc.x), int(grid_loc.y)];
				            if (cell != nil) {
				                draw "Height: " + (round(cell.height * 100) / 100) + "m" 
				                    at: {2, 10} color: #orange font: font("Default", 10, #bold);
				            }
				        }
				    }
	        }
	        
        }
		monitor "Current Cycle" value: cycle;
		monitor "Current Time" value: (int(current_time) < 10 ? "0" : "") + string(int(current_time)) + ":" + (int((current_time - int(current_time)) * 60) < 10 ? "0" : "") + string(int((current_time - int(current_time)) * 60));
	    monitor "Day/Night" value: (current_time >= evening_start or current_time < morning_end) ? "Night" : "Day";
     	monitor "Average Height" value: mean(Beach_Cell collect each.height);
	    monitor "Tide Level" value: round(current_tide * 100) / 100;
	    monitor "Highest Pile Value" value: empty(WoodPile) ? 0 : max(WoodPile collect each.pile_value);
	    monitor "Average Pile Stability" value: empty(WoodPile) ? 0 : (mean(WoodPile collect (	min(1.0,max(0.0, each.stability_score)))) with_precision 2);
        monitor "Active Collectors" value: length(Collector);
		monitor "Active Wood Pieces" value: length(Driftwood);
		monitor "Active Piles" value: length(WoodPile);
        monitor "Total Thefts" value: sum(WoodPile collect each.times_stolen_from);
        monitor "Active Authorities" value: length(Authority);
		monitor "Active Pursuits" value: active_pursuits;
		monitor "Total Catches" value: total_catches;
		monitor "System Stability" value: system_stability;
        monitor "Number of Groups" value: length(Collector where each.is_group_leader);
        monitor "Grouped Collectors" value: length(Collector where each.in_group);
        monitor "Average Group Size" value: empty(Collector where each.is_group_leader) ? 0 : mean(Collector where each.is_group_leader collect length(each.group_members));
		display "Group Performance Analysis" refresh: every(5 #cycles) {
		    chart "Group vs Solo Performance" type: series style: line 
		    background: rgb(255,255,255) size: {1.0, 0.5} position: {0, 0} 
		    {
		        data "Avg Group Collection" value: mean(Collector where (each.in_group) collect each.wood_collected_count) color: #blue;
		        data "System Stability" value: system_stability color: #green;
		        data "Perturbation Level" value: system_perturbation color: #red;
		    }
		    chart "Group Distribution" type: pie 
		    background: rgb(255,255,255) size: {1.0, 0.5} position: {0, 0.5} 
		    {
		        data "Solo Collectors" value: length(Collector where (!each.in_group)) color: #gray;
		        loop leader over: Collector where (each.is_group_leader) {
		            data "Group " + leader.group_id 
		            value: length(leader.group_members) 
		            color: leader.group_color;
		        }
		    }
		}
        display "Performance Analysis" refresh: every(5 #cycles) {
		    chart "Detailed Metrics"
				type: series style: line 
		    	background: rgb(255,255,255) 
		{
		        data "Group Efficiency" value: calculate_solo_vs_group_efficiency() color: #blue;
		        data "Groups Count" value: length(Collector where each.is_group_leader) color: #orange;
		        data "Active Perturbation" value: perturbation_active ? 1.0 : 0.0 color: #red;
		    }
		}
		
		        
    }

}



