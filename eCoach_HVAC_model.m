%% eCoach_HVAC_model.m
% =========================================================================
% eCoach (electric intercity bus) HVAC hot-water circuit - SINGLE FILE
%
% Builds the Simulink model eCoach_HVAC_Water_Circuit.slx (once), then runs
% it with the values of its Parameters block, draws 6 figures, prints KPIs.
%
% Requirements : MATLAB + Simulink only (target R2020b).
%                No Simscape / Simscape Fluids / other toolbox is used.
%
% HOW TO USE
%   eCoach_HVAC_model                    % first time: build + checks + run
%   -> in the model, double-click the yellow "Parameters" block, change any
%      value, press OK, then press Run in Simulink (or run this file again).
%   -> open the "Results" block: Scopes + live Displays (kWh, faults, ...).
%
%   run_scenario = 3; eCoach_HVAC_model  % set the scenario from the command line
%   run_checks = true; eCoach_HVAC_model % run the PASS/FAIL checks again
%   rebuild_model = true; eCoach_HVAC_model % build the .slx from scratch
%                                          (resets the Parameters block)
%
% Scenarios 0-2 run until the cabin reaches the setpoint (Parameters: max
% time, tolerance) and report the TIME TO SETPOINT.
% Scenarios: 0 custom (values in the dialog), 1 cold start (-10 degC),
%            2 mild weather (+10 degC), 3 all consumer valves closed
%            600..780 s (bypass check), 4 pump capacity drops to 2 % at 600 s.
%
% Physical approach (lumped, first principles):
%   - Hydraulics: pump curve dp = dp0*n^2 - K*m^2, quadratic losses
%     dp = (m/G)^2 for pipes / valves / restrictions, parallel branches,
%     check-valve cracking pressure, valve leakage when closed; network
%     solved every time step (bisection on the supply-return pressure).
%   - Thermal: 12 water temperature states, e-NTU heat release in frontboxes
%     and convectors, metal thermal mass, 2-state cabin (air + structure).
%   - Control: discrete (0.1 s) supervisory controller with hysteresis,
%     PI + anti-windup, pump / valve / fan / pre-heater logic.
%   - Safety: latched faults, heater shutdown, bypass open, pump cooldown.
% =========================================================================

modelName = 'eCoach_HVAC_Water_Circuit';
if ~exist('rebuild_model', 'var') || isempty(rebuild_model), rebuild_model = false; end

fprintf('\n=============== eCoach HVAC model (single file) ===============\n');
fprintf('MATLAB version : %s\n', version);
vSL = ver('simulink');
if isempty(vSL) || ~license('test', 'Simulink')
    error('eCoach:env', 'Simulink is required.');
end
fprintf('Simulink       : %s %s\n', vSL.Version, vSL.Release);

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir), rootDir = pwd; end
slxFile = fullfile(rootDir, [modelName '.slx']);

%% 1. Build the model (only when missing, outdated or rebuild_model = true)
justBuilt = false;
if ~rebuild_model && exist(slxFile, 'file')
    load_system(slxFile);
    if getSimulinkBlockHandle([modelName '/Parameters']) == -1 || ...
            getSimulinkBlockHandle([modelName '/Results/Setpoint_Reach_Detector']) == -1
        fprintf('Existing model is an older version -> rebuilding.\n');
        rebuild_model = true;
    end
end
if rebuild_model || ~exist(slxFile, 'file')
    ecoach_build(modelName, rootDir);
    justBuilt = true;
end
open_system(modelName);

%% 2. Optional scenario selection from the Command Window
if exist('run_scenario', 'var') && ~isempty(run_scenario)
    setScenario(modelName, run_scenario);
end

%% 3. Automatic checks (default: only right after a build)
if ~exist('run_checks', 'var') || isempty(run_checks), run_checks = justBuilt; end
if run_checks
    ecoach_verify(modelName, rootDir);
end

%% 4. Simulate with the values of the Parameters block, plot, KPIs
eCoachResults = ecoach_run(modelName);
P = evalin('base', 'ecoach_P');
ecoach_plots(eCoachResults, P);
ecoach_kpis(eCoachResults, P);
save_system(modelName);
clear run_scenario run_checks rebuild_model justBuilt


%% =========================================================================
%%            PARAMETERS (Parameters block dialog + model InitFcn)
%% =========================================================================
function code = init_code(M)
% Code stored in the model InitFcn: runs before every simulation / update,
% reads the Parameters block dialog and writes all variables to the base
% workspace. The .slx therefore also runs with the Simulink Run button.
L = {
'% eCoach HVAC - parameter initialisation (model InitFcn).'
'% Reads the "Parameters" block dialog and writes all model variables to the'
'% base workspace. Runs automatically before every simulation / update.'
'ecoachPB = ''__MODEL__/Parameters'';'
'ecoach_txt = @(n) get_param(ecoachPB, n);'
'ecoach_num = @(n) eval(get_param(ecoachPB, n));'
''
'% ---------- scenario / simulation ----------'
'ecoach_s = ecoach_txt(''test_scenario'');'
'test_scenario = str2double(ecoach_s(1));'
'Tstop = ecoach_num(''sim_time_s'');'
'amb_C = ecoach_num(''ambient_C'');'
'cab0_C = ecoach_num(''cabin_initial_C'');'
'sp_C = ecoach_num(''setpoint_C'');'
'number_of_passengers = ecoach_num(''passengers'');'
'solar_load_W = ecoach_num(''solar_W'');'
'door_heat_loss_W = ecoach_num(''door_loss_W'');'
't_hvac_on = ecoach_num(''hvac_on_time_s'');'
'stop_at_setpoint_on = strcmp(ecoach_txt(''stop_at_setpoint''), ''on'');'
'max_sim_time_s = ecoach_num(''max_sim_time_s'');'
'reach_tolerance_K = ecoach_num(''reach_tolerance_K'');'
'switch test_scenario'
'    case 1, Tstop = 3600; amb_C = -10; cab0_C = 0;  sp_C = 20;'
'    case 2, Tstop = 3600; amb_C = 10;  cab0_C = 12; sp_C = 20;'
'    case 3, Tstop = 1800; amb_C = -10; cab0_C = 0;  sp_C = 20;'
'    case 4, Tstop = 1500; amb_C = -10; cab0_C = 0;  sp_C = 20;'
'end'
'% "run until the cabin reaches the setpoint" (scenarios 0, 1, 2 only;'
'% scenarios 3 and 4 are fault tests with fixed duration)'
'stop_at_setpoint = double(stop_at_setpoint_on && test_scenario <= 2);'
'if stop_at_setpoint'
'    Tstop = max_sim_time_s;'
'end'
''
'% ---------- fluid: 50/50 water / ethylene glycol (constant properties) ----'
'fluid_density_kg_m3             = 1060;'
'fluid_cp_J_kgK                  = 3400;'
'fluid_dynamic_viscosity_Pa_s    = 0.005;'
'fluid_thermal_conductivity_W_mK = 0.4;'
'fluid_initial_temperature_K     = 293.15;'
'system_initial_pressure_Pa      = 150000;'
''
'% ---------- heaters ----------'
'P_HVH_nominal_W        = ecoach_num(''P_HVH_nominal_W'');'
'heater_efficiency      = ecoach_num(''heater_efficiency'');'
'T_heater_max_K         = ecoach_num(''T_heater_max_C'') + 273.15;'
'T_heater_min_enable_K  = 278.15;'
'hvh_min_flow_kg_s      = 0.08;'
'heater_rate_up_1_s     = 0.2;'
'heater_rate_down_1_s   = 10;'
'heater_time_constant_s = 2.0;'
'hvh_fluid_volume_m3    = 0.0010;'
'hvh_dp_nominal_Pa      = 3000;'
'P_preheater_nominal_W  = ecoach_num(''P_preheater_nominal_W'');'
'preheater_efficiency   = ecoach_num(''preheater_efficiency'');'
'preheater_mode         = ecoach_txt(''preheater_mode'');'
'preheater_fluid_volume_m3   = 0.0005;'
'preheater_dp_nominal_Pa     = 2000;'
'preheater_mdot_nominal_kg_s = 0.06;'
'preheater_restriction_dp_Pa = 25000;'
''
'% ---------- pumps ----------'
'pump_dp_nominal_Pa      = ecoach_num(''pump_dp_nominal_Pa'');'
'pump_mdot_nominal_kg_s  = ecoach_num(''pump_mdot_nominal_kg_s'');'
'pump_efficiency         = ecoach_num(''pump_efficiency'');'
'pump_speed_nominal_rpm  = 4000;'
'pump_time_constant_s    = 0.5;'
'pump_rate_1_s           = 1.0;'
'pump_dp0_Pa             = 1.5*pump_dp_nominal_Pa;'
'pump_K_int              = (pump_dp0_Pa - pump_dp_nominal_Pa)/pump_mdot_nominal_kg_s^2;'
'hc_pump_dp_nominal_Pa   = ecoach_num(''hc_pump_dp_nominal_Pa'');'
'hc_pump_mdot_nominal_kg_s = 0.4;'
'hc_pump_dp0_Pa          = 1.5*hc_pump_dp_nominal_Pa;'
'hc_pump_K_int           = (hc_pump_dp0_Pa - hc_pump_dp_nominal_Pa)/hc_pump_mdot_nominal_kg_s^2;'
''
'% ---------- valves ----------'
'check_valve_cracking_pressure_Pa = ecoach_num(''check_valve_cracking_pressure_Pa'');'
'check_valve_dp_nominal_Pa        = 3000;'
'two_way_valve_nominal_dp_Pa      = 20000;'
'two_way_valve_nominal_mdot_kg_s  = 0.4;'
'three_way_valve_nominal_dp_Pa    = 15000;'
'three_way_valve_nominal_mdot_kg_s = 0.4;'
'bypass_valve_nominal_dp_Pa       = 15000;'
'bypass_valve_nominal_mdot_kg_s   = 0.25;'
'bypass_restriction_dp_nominal_Pa = 15000;'
'bypass_min_mdot_kg_s             = ecoach_num(''bypass_min_mdot_kg_s'');'
'bypass_min_open                  = 0.3;'
'valve_actuator_time_constant_s   = ecoach_num(''valve_actuator_time_constant_s'');'
'valve_rate_1_s                   = 0.2;'
'valve_leakage_fraction           = ecoach_num(''valve_leakage_fraction'');'
''
'% ---------- frontbox / convectors ----------'
'frontbox_connection_mode        = ecoach_txt(''frontbox_connection_mode'');'
'frontbox_UA_W_K                 = ecoach_num(''frontbox_UA_W_K'');'
'frontbox_effectiveness          = ecoach_num(''frontbox_effectiveness'');'
'frontbox_water_dp_nominal_Pa    = 15000;'
'frontbox_mdot_nominal_kg_s      = 0.15;'
'frontbox_fluid_volume_m3        = 0.0015;'
'frontbox_balance_dp_nominal_Pa  = 5000;'
'frontbox_fan_nominal_power_W    = ecoach_num(''frontbox_fan_nominal_power_W'');'
'frontbox_air_C_nominal_W_K      = 450;'
'frontbox_air_natural_fraction   = 0.05;'
'frontbox_metal_thermal_mass_J_K = 8000;'
'fan_time_constant_s             = 3.0;'
'convector_UA_each_W_K            = ecoach_num(''convector_UA_each_W_K'');'
'convector_fluid_volume_each_m3   = 0.0008;'
'convector_dp_each_Pa             = 5000;'
'convector_mdot_nominal_kg_s      = 0.15;'
'convector_metal_thermal_mass_J_K = ecoach_num(''convector_metal_thermal_mass_J_K'');'
''
'% ---------- tank, air separator, pipes ----------'
'tank_volume_m3             = 0.015;'
'tank_initial_temperature_K = 293.15;'
'tank_initial_pressure_Pa   = 150000;'
'air_sep_volume_m3          = pi/4*0.08^2*0.30;'
'air_sep_dp_nominal_Pa      = 2000;'
'main_pipe_length_m         = 8;'
'main_pipe_diameter_m       = 0.025;'
'branch_pipe_diameter_m     = 0.018;'
'branch_pipe_length_m       = 3;'
'local_pipe_length_m        = 1;'
'bypass_pipe_length_m       = 1.5;'
'pipe_roughness_m           = 1.5e-5;'
'pipe_wall_thermal_mass_J_K = 5000;'
''
'% ---------- cabin ----------'
'T_ambient_initial_K                  = amb_C + 273.15;'
'T_cabin_initial_K                    = cab0_C + 273.15;'
'cabin_air_thermal_capacity_J_K       = ecoach_num(''cabin_air_thermal_capacity_J_K'');'
'cabin_structure_thermal_capacity_J_K = ecoach_num(''cabin_structure_thermal_capacity_J_K'');'
'cabin_ambient_UA_W_K                 = ecoach_num(''cabin_ambient_UA_W_K'');'
'cabin_air_structure_UA_W_K           = ecoach_num(''cabin_air_structure_UA_W_K'');'
'passenger_heat_per_person_W          = ecoach_num(''passenger_heat_per_person_W'');'
'cabin_sensor_offset_front_K          = 0.3;'
'cabin_sensor_offset_rear_K           = -0.3;'
''
'% ---------- sensors / control / solver ----------'
'water_sensor_tau_s = 3.0;'
'flow_sensor_tau_s  = 0.5;'
'cabin_sensor_tau_s = 15.0;'
'Ts_ctrl            = ecoach_num(''Ts_ctrl'');'
'Kp_heater          = ecoach_num(''Kp_heater'');'
'Ki_heater          = ecoach_num(''Ki_heater'');'
'max_step_s         = 0.5;'
'rel_tol            = 1e-3;'
'log_sample_time_s  = 1;'
''
'% ---------- scenario signals (From Workspace tables [t value]) ----------'
'scn_setpoint      = [0 sp_C; Tstop sp_C];'
'scn_ambient       = [0 amb_C; Tstop amb_C];'
'scn_ignition      = [0 1; Tstop 1];'
'scn_hvac_enable   = [0 0; t_hvac_on 0; t_hvac_on 1; Tstop 1];'
'scn_fault_reset   = [0 0; Tstop 0];'
'scn_passengers    = [0 number_of_passengers; Tstop number_of_passengers];'
'scn_solar         = [0 solar_load_W; Tstop solar_load_W];'
'scn_door          = [0 door_heat_loss_W; Tstop door_heat_loss_W];'
'scn_valve_close   = [0 0; Tstop 0];'
'scn_pump_capacity = [0 1; Tstop 1];'
'if test_scenario == 3'
'    scn_valve_close = [0 0; 600 0; 600 1; 780 1; 780 0; Tstop 0];'
'elseif test_scenario == 4'
'    scn_pump_capacity = [0 1; 600 1; 600 0.02; Tstop 0.02];'
'end'
''
'% ---------- mode ids ----------'
'frontbox_mode_id = 1 + strcmp(frontbox_connection_mode, ''series'');'
'preheater_mode_id = find(strcmp(preheater_mode, {''auxiliary_heat'', ''cold_start_preheat'', ''disabled''}), 1);'
''
'% ---------- hydraulic conductances G = mdot/sqrt(dp) ----------'
'ecoach_fturb = @(R, D) (-1.8*log10((pipe_roughness_m/D/3.7)^1.11 + 6.9/R))^-2;'
'ecoach_Re = @(D, m) max(fluid_density_kg_m3*(m/(fluid_density_kg_m3*pi/4*D^2))*D/fluid_dynamic_viscosity_Pa_s, 1);'
'ecoach_w = @(R) min(max((R - 2000)/2000, 0), 1);'
'ecoach_f = @(D, m) (ecoach_Re(D, m) <= 2000)*64/ecoach_Re(D, m) ...'
'    + (ecoach_Re(D, m) >= 4000)*ecoach_fturb(ecoach_Re(D, m), D) ...'
'    + (ecoach_Re(D, m) > 2000 && ecoach_Re(D, m) < 4000)*((1 - ecoach_w(ecoach_Re(D, m)))*64/2000 + ecoach_w(ecoach_Re(D, m))*ecoach_fturb(4000, D));'
'ecoach_dp = @(L, D, m) ecoach_f(D, m)*L/D*fluid_density_kg_m3*(m/(fluid_density_kg_m3*pi/4*D^2))^2/2;'
'Gp = @(L, D, m) m/sqrt(ecoach_dp(L, D, m));'
'Gn = @(m, dp) m/sqrt(dp);'
'gser = @(Gs) 1/sqrt(sum(1./Gs.^2));'
'Vp = @(L, D) pi/4*D^2*L;'
'ecoach_Lm = main_pipe_length_m/2;'
'G_pump_int = 1/sqrt(pump_K_int);'
'G_hc_int   = 1/sqrt(hc_pump_K_int);'
'G_main = gser([Gp(ecoach_Lm, main_pipe_diameter_m, 0.8), Gp(ecoach_Lm, main_pipe_diameter_m, 0.8), ...'
'    Gn(0.8, air_sep_dp_nominal_Pa), G_pump_int, Gn(0.8, check_valve_dp_nominal_Pa), Gn(0.8, hvh_dp_nominal_Pa)]);'
'G_branch  = Gp(branch_pipe_length_m, branch_pipe_diameter_m, 0.3);'
'G_local   = Gp(local_pipe_length_m, branch_pipe_diameter_m, 0.3);'
'G_fb_line = gser([G_branch, G_branch]);'
'G_fb_hx   = Gn(frontbox_mdot_nominal_kg_s, frontbox_water_dp_nominal_Pa);'
'G_fb_bal  = Gn(frontbox_mdot_nominal_kg_s, frontbox_balance_dp_nominal_Pa);'
'G_fb_unit = gser([G_fb_bal, G_fb_hx]);'
'G_three_way = Gn(three_way_valve_nominal_mdot_kg_s, three_way_valve_nominal_dp_Pa);'
'G_two_way   = Gn(two_way_valve_nominal_mdot_kg_s, two_way_valve_nominal_dp_Pa);'
'G_cv_line  = gser([G_branch, G_branch, G_local]);'
'G_cv_chain = Gn(convector_mdot_nominal_kg_s, 3*convector_dp_each_Pa);'
'G_cv_bank  = gser([2*G_cv_chain, G_local, G_local]);'
'G_ph = gser([G_branch, Gn(preheater_mdot_nominal_kg_s, preheater_restriction_dp_Pa), ...'
'    Gn(preheater_mdot_nominal_kg_s, preheater_dp_nominal_Pa), G_branch]);'
'G_bp_valve = Gn(bypass_valve_nominal_mdot_kg_s, bypass_valve_nominal_dp_Pa);'
'G_bp_fixed = gser([Gp(bypass_pipe_length_m, branch_pipe_diameter_m, 0.25), ...'
'    Gn(bypass_valve_nominal_mdot_kg_s, bypass_restriction_dp_nominal_Pa)]);'
''
'% ---------- thermal capacities of the water nodes ----------'
'ecoach_rc = fluid_density_kg_m3*fluid_cp_J_kgK;'
'ecoach_Vret = Vp(ecoach_Lm, main_pipe_diameter_m) + tank_volume_m3 + air_sep_volume_m3 ...'
'    + 3*Vp(branch_pipe_length_m, branch_pipe_diameter_m) + Vp(bypass_pipe_length_m, branch_pipe_diameter_m);'
'ecoach_Vsup = Vp(ecoach_Lm, main_pipe_diameter_m) + 3*Vp(branch_pipe_length_m, branch_pipe_diameter_m) ...'
'    + 3*Vp(local_pipe_length_m, branch_pipe_diameter_m);'
'lumped_x0 = fluid_initial_temperature_K*ones(12, 1);'
''
'% ---------- hvacP: numeric struct used by all MATLAB Function blocks ----------'
'hvacP = struct();'
'hvacP.Ts_ctrl = Ts_ctrl;  hvacP.Kp_heater = Kp_heater;  hvacP.Ki_heater = Ki_heater;'
'hvacP.Tt_antiwindup = 50;'
'hvacP.hyst_on_C = ecoach_num(''hyst_on_C'');  hvacP.hyst_off_C = ecoach_num(''hyst_off_C'');'
'hvacP.stop_at_setpoint = stop_at_setpoint;'
'hvacP.reach_tol_K = reach_tolerance_K;'
'hvacP.t_hvac_on = t_hvac_on;'
'hvacP.T_HVH_derate_start_C = T_heater_max_K - 273.15 - 10;'
'hvacP.T_HVH_derate_end_C = T_heater_max_K - 273.15 - 5;'
'hvacP.pump_min_speed = 0.3;  hvacP.dT_sr_full_speed_C = 15;'
'hvacP.mdot_boost_threshold_kg_s = 0.25;  hvacP.pump_postrun_s = 60;'
'hvacP.valve_mod_band_C = 3;  hvacP.valve_min_open_heating = 0.1;'
'hvacP.cv2_min_open = 0.3;    hvacP.bypass_min_open = bypass_min_open;'
'hvacP.hc_pump_min_speed = 0.4;'
'hvacP.fan_water_dT_min_C = 8;  hvacP.fan_min_cmd = 0.25;  hvacP.fan_band_C = 4;'
'hvacP.preheater_mode_id = preheater_mode_id;'
'hvacP.preheater_ambient_on_C = -5;  hvacP.preheater_sat_delay_s = 60;'
'hvacP.preheater_cold_on_C = 15;     hvacP.preheater_cold_off_C = 25;'
'hvacP.preheater_cold_ambient_C = 5;'
'hvacP.T_heater_min_enable_C = T_heater_min_enable_K - 273.15;'
'hvacP.T_heater_max_C = T_heater_max_K - 273.15;'
'hvacP.overtemp_debounce_s = 0.5;'
'hvacP.mdot_low_flow_kg_s = ecoach_num(''mdot_low_flow_kg_s'');'
'hvacP.lowflow_arm_s = 8;  hvacP.lowflow_debounce_s = 1;'
'hvacP.p_max_Pa = 4.0e5;  hvacP.pressure_debounce_s = 0.5;'
'hvacP.pump_dp_nominal_Pa = pump_dp_nominal_Pa;'
'hvacP.pump_fault_dp_frac = 0.25;  hvacP.pump_fault_debounce_s = 3;'
'hvacP.freeze_risk_C = -30;'
'hvacP.valve_mismatch_tol = 0.25;  hvacP.valve_mismatch_time_s = 20;'
'hvacP.cabin_overtemp_C = 32;'
'hvacP.cooldown_s = 120;  hvacP.cooldown_speed = 0.5;  hvacP.freeze_pump_speed = 0.3;'
'hvacP.sensor_T_min_K = 200;  hvacP.sensor_T_max_K = 420;'
'hvacP.T_heater_max_K = T_heater_max_K;  hvacP.hvh_min_flow_kg_s = hvh_min_flow_kg_s;'
'hvacP.cp = fluid_cp_J_kgK;'
'hvacP.frontbox_mode_id = frontbox_mode_id;'
'hvacP.frontbox_UA_W_K = frontbox_UA_W_K;'
'hvacP.frontbox_effectiveness = frontbox_effectiveness;'
'hvacP.frontbox_air_C_nominal_W_K = frontbox_air_C_nominal_W_K;'
'hvacP.frontbox_air_natural_fraction = frontbox_air_natural_fraction;'
'hvacP.frontbox_fan_nominal_power_W = frontbox_fan_nominal_power_W;'
'hvacP.convector_UA_each_W_K = convector_UA_each_W_K;'
'hvacP.C_air = cabin_air_thermal_capacity_J_K;  hvacP.C_struct = cabin_structure_thermal_capacity_J_K;'
'hvacP.UA_amb = cabin_ambient_UA_W_K;  hvacP.UA_as = cabin_air_structure_UA_W_K;'
'hvacP.q_person = passenger_heat_per_person_W;'
'hvacP.off_front = cabin_sensor_offset_front_K;  hvacP.off_rear = cabin_sensor_offset_rear_K;'
'hvacP.leak = valve_leakage_fraction;'
'hvacP.dp0_main = pump_dp0_Pa;  hvacP.G_pump_int = G_pump_int;'
'hvacP.dp0_hc = hc_pump_dp0_Pa;  hvacP.G_hc_int = G_hc_int;'
'hvacP.check_crack = check_valve_cracking_pressure_Pa;'
'hvacP.G_main = G_main;'
'hvacP.G_fb_line = G_fb_line;  hvacP.G_fb_cons_fixed = G_local;'
'hvacP.G_fb_unit = G_fb_unit;  hvacP.G_fb_hx = G_fb_hx;  hvacP.G_fb_bal = G_fb_bal;'
'hvacP.G_fb_bpp = G_local;'
'hvacP.G_three_way = G_three_way;  hvacP.G_two_way = G_two_way;'
'hvacP.G_cv_line = G_cv_line;  hvacP.G_cv_bank = G_cv_bank;  hvacP.G_cv_bpp = G_local;'
'hvacP.G_ph = G_ph;  hvacP.G_bp_fixed = G_bp_fixed;  hvacP.G_bp_valve = G_bp_valve;'
'hvacP.p_tank = tank_initial_pressure_Pa;'
'hvacP.C_ret = ecoach_rc*ecoach_Vret + 0.5*pipe_wall_thermal_mass_J_K;'
'hvacP.C_sup = ecoach_rc*ecoach_Vsup + 0.5*pipe_wall_thermal_mass_J_K;'
'hvacP.C_hvh = ecoach_rc*hvh_fluid_volume_m3;'
'hvacP.C_fb  = ecoach_rc*frontbox_fluid_volume_m3;'
'hvacP.C_cv  = ecoach_rc*convector_fluid_volume_each_m3;'
'hvacP.C_ph  = ecoach_rc*preheater_fluid_volume_m3;'
''
'% ---------- summary struct for the script (plots / KPIs) ----------'
'ecoach_P = struct(''test_scenario'', test_scenario, ''Tstop'', Tstop, ''t_hvac_on'', t_hvac_on, ...'
'    ''bypass_min_mdot_kg_s'', bypass_min_mdot_kg_s, ''T_heater_max_K'', T_heater_max_K, ''setpoint_C'', sp_C, ...'
'    ''reach_tol_K'', reach_tolerance_K, ''stop_at_setpoint'', stop_at_setpoint);'
'if ~all(cellfun(@(v) all(isfinite(v(:))), struct2cell(hvacP))) || Tstop <= 0 || isempty(preheater_mode_id)'
'    error(''eCoach:param'', ''Invalid value in the Parameters block (check the dialog entries).'');'
'end'
'fprintf(''eCoach parameters applied: scenario %d, max %g s, ambient %g degC, setpoint %g degC, HVH %g kW, stop at setpoint: %d\n'', ...'
'    test_scenario, Tstop, amb_C, sp_C, P_HVH_nominal_W/1e3, stop_at_setpoint);'
'clear ecoachPB ecoach_txt ecoach_num ecoach_s stop_at_setpoint_on ecoach_fturb ecoach_Re ecoach_w ecoach_f ecoach_dp'
'clear Gp Gn gser Vp ecoach_Lm ecoach_rc ecoach_Vret ecoach_Vsup'
};
code = strrep(strjoin(L, newline), '__MODEL__', M);
end

function P = applyParams(M)
% Runs the model InitFcn now (same code Simulink runs before a simulation).
evalin('base', get_param(M, 'InitFcn'));
P = evalin('base', 'ecoach_P');
end

function opts = scenarioOptions()
opts = {'0 - Custom (values below)', '1 - Cold start (-10 C)', '2 - Mild weather (+10 C)', ...
        '3 - Valve closure / bypass test', '4 - Pump failure / low-flow test'};
end

function setScenario(M, k)
opts = scenarioOptions();
if ~isnumeric(k) || k < 0 || k > 4 || k ~= round(k)
    error('eCoach:scenario', 'run_scenario must be 0..4');
end
set_param([M '/Parameters'], 'test_scenario', opts{k + 1});
fprintf('Parameters block: scenario set to "%s"\n', opts{k + 1});
end

function addParametersBlock(M)
% Masked block without ports: double-click opens the parameter dialog.
blk = addSub(M, 'Parameters', [40 -160 220 -40]);
set_param(blk, 'BackgroundColor', '[1 1 0.75]', 'ForegroundColor', 'black');
mk = Simulink.Mask.create(blk);
mk.Display = sprintf('disp(''PARAMETERS\\n(double-click)'')');
mk.IconOpaque = 'opaque';
mk.Description = sprintf(['eCoach HVAC water circuit - all model parameters.\n' ...
    'Scenarios 1..4 override sim time, ambient, initial cabin and setpoint; choose "0 - Custom" to use ' ...
    'the values entered below. Values are applied automatically at every Run (model InitFcn).']);
% {tab, name, prompt, type, value}
pr = {
 'Scenario', 'test_scenario', 'Test scenario', 'popup', '1 - Cold start (-10 C)'
 'Scenario', 'sim_time_s', 'Simulation stop time [s] (custom)', 'edit', '3600'
 'Scenario', 'ambient_C', 'Ambient temperature [degC] (custom)', 'edit', '-10'
 'Scenario', 'cabin_initial_C', 'Initial cabin temperature [degC] (custom)', 'edit', '0'
 'Scenario', 'setpoint_C', 'Cabin setpoint [degC] (custom)', 'edit', '20'
 'Scenario', 'passengers', 'Number of passengers [-]', 'edit', '40'
 'Scenario', 'solar_W', 'Solar load [W]', 'edit', '0'
 'Scenario', 'door_loss_W', 'Door opening heat loss [W]', 'edit', '0'
 'Scenario', 'hvac_on_time_s', 'HVAC enable time [s]', 'edit', '10'
 'Scenario', 'stop_at_setpoint', 'Run until the cabin reaches the setpoint (scenarios 0-2)', 'checkbox', 'on'
 'Scenario', 'max_sim_time_s', 'Maximum simulation time when running to setpoint [s]', 'edit', '28800'
 'Scenario', 'reach_tolerance_K', 'Setpoint reached when cabin >= setpoint - tolerance [K]', 'edit', '0.2'
 'Heaters', 'P_HVH_nominal_W', 'High Voltage Heater nominal power [W]', 'edit', '30000'
 'Heaters', 'heater_efficiency', 'High Voltage Heater efficiency [-]', 'edit', '0.95'
 'Heaters', 'T_heater_max_C', 'Heater outlet trip temperature [degC]', 'edit', '90'
 'Heaters', 'P_preheater_nominal_W', 'Pre-heater nominal power [W]', 'edit', '5000'
 'Heaters', 'preheater_efficiency', 'Pre-heater efficiency [-]', 'edit', '0.9'
 'Heaters', 'preheater_mode', 'Pre-heater mode', 'popup', 'auxiliary_heat'
 'Pumps & valves', 'pump_dp_nominal_Pa', 'Main pump nominal pressure rise [Pa]', 'edit', '80000'
 'Pumps & valves', 'pump_mdot_nominal_kg_s', 'Main pump nominal mass flow [kg/s]', 'edit', '0.8'
 'Pumps & valves', 'pump_efficiency', 'Pump efficiency [-]', 'edit', '0.55'
 'Pumps & valves', 'hc_pump_dp_nominal_Pa', 'Heating circuit pump nominal pressure rise [Pa]', 'edit', '40000'
 'Pumps & valves', 'check_valve_cracking_pressure_Pa', 'Check valve cracking pressure [Pa]', 'edit', '5000'
 'Pumps & valves', 'bypass_min_mdot_kg_s', 'Minimum bypass flow (test limit) [kg/s]', 'edit', '0.1'
 'Pumps & valves', 'valve_actuator_time_constant_s', 'Valve actuator time constant [s]', 'edit', '1.0'
 'Pumps & valves', 'valve_leakage_fraction', 'Closed valve leakage fraction [-]', 'edit', '1e-3'
 'Consumers', 'frontbox_connection_mode', 'Frontbox connection', 'popup', 'parallel'
 'Consumers', 'frontbox_UA_W_K', 'Frontbox UA [W/K]', 'edit', '800'
 'Consumers', 'frontbox_effectiveness', 'Frontbox effectiveness [-]', 'edit', '0.65'
 'Consumers', 'frontbox_fan_nominal_power_W', 'Frontbox fan nominal power [W]', 'edit', '300'
 'Consumers', 'convector_UA_each_W_K', 'Convector UA, each [W/K]', 'edit', '250'
 'Consumers', 'convector_metal_thermal_mass_J_K', 'Convector metal thermal mass, each [J/K]', 'edit', '12000'
 'Cabin', 'cabin_air_thermal_capacity_J_K', 'Cabin air thermal capacity [J/K]', 'edit', '500000'
 'Cabin', 'cabin_structure_thermal_capacity_J_K', 'Interior structure thermal capacity [J/K]', 'edit', '5000000'
 'Cabin', 'cabin_ambient_UA_W_K', 'Cabin-ambient UA [W/K]', 'edit', '1200'
 'Cabin', 'cabin_air_structure_UA_W_K', 'Air-structure UA [W/K]', 'edit', '800'
 'Cabin', 'passenger_heat_per_person_W', 'Heat per passenger [W]', 'edit', '100'
 'Control', 'Kp_heater', 'Heater PI Kp [1/K]', 'edit', '0.12'
 'Control', 'Ki_heater', 'Heater PI Ki [1/(K s)]', 'edit', '0.003'
 'Control', 'hyst_on_C', 'Heating request ON when error > [K]', 'edit', '1.0'
 'Control', 'hyst_off_C', 'Heating request OFF when error < [K]', 'edit', '0.2'
 'Control', 'Ts_ctrl', 'Controller sample time [s]', 'edit', '0.1'
 'Control', 'mdot_low_flow_kg_s', 'Low-flow fault threshold [kg/s]', 'edit', '0.12'
};
popups = struct('test_scenario', {scenarioOptions()}, ...
    'preheater_mode', {{'auxiliary_heat', 'cold_start_preheat', 'disabled'}}, ...
    'frontbox_connection_mode', {{'parallel', 'series'}});
tabNames = unique(pr(:, 1), 'stable');
useTabs = true;
try
    tc = mk.addDialogControl('tabcontainer', 'ParamTabs');
    for k = 1:numel(tabNames)
        tb = tc.addDialogControl('tab', sprintf('Tab%d', k));
        tb.Prompt = tabNames{k};
    end
catch
    useTabs = false;   % older release: one flat dialog
end
for k = 1:size(pr, 1)
    args = {'Name', pr{k, 2}, 'Prompt', pr{k, 3}, 'Type', pr{k, 4}, 'Evaluate', 'off'};
    if any(strcmp(pr{k, 2}, {'test_scenario', 'sim_time_s', 'stop_at_setpoint', 'max_sim_time_s'}))
        % apply immediately so that the model StopTime (= Tstop) is up to date
        args = [args, {'Callback', 'try, evalin(''base'', get_param(bdroot(gcb), ''InitFcn'')); catch, end'}]; %#ok<AGROW>
    end
    if strcmp(pr{k, 4}, 'popup')
        args = [args, {'TypeOptions', popups.(pr{k, 2})}]; %#ok<AGROW>
    end
    if useTabs
        args = [args, {'Container', sprintf('Tab%d', find(strcmp(tabNames, pr{k, 1})))}]; %#ok<AGROW>
    end
    mk.addParameter(args{:});
    set_param(blk, pr{k, 2}, pr{k, 5});
end
set_param(M, 'InitFcn', init_code(M));       % before every simulation / update
set_param(M, 'PostLoadFcn', init_code(M));   % when the .slx is opened
end


%% =========================================================================
%%                                 BUILD
%% =========================================================================
function ecoach_build(M, rootDir)
fprintf('Building model %s ...\n', M);
load_system('simulink');
if bdIsLoaded(M), close_system(M, 0); end
slxFile = fullfile(rootDir, [M '.slx']);
if exist(slxFile, 'file'), delete(slxFile); end
new_system(M);
open_system(M);
cfg = {'SolverType', 'Variable-step'; 'Solver', 'ode23t'; 'StopTime', 'Tstop'; ...
       'MaxStep', 'max_step_s'; 'RelTol', 'rel_tol'; 'ReturnWorkspaceOutputs', 'on'; ...
       'AlgebraicLoopMsg', 'warning'};
for k = 1:size(cfg, 1)
    set_param(M, cfg{k, 1}, cfg{k, 2});
end
addParametersBlock(M);     % masked dialog + model InitFcn

% ---------------- top-level subsystems (layout: left -> right, top -> bottom)
TS = addSub(M, 'Test_Scenarios',                  [  40  60  220 600]);
HV = addSub(M, 'High_Voltage_Heater',             [ 420  40  620 200]);
PH = addSub(M, 'PreHeater_Branch',                [ 420 240  620 360]);
FB = addSub(M, 'Frontbox_Branch',                 [ 420 400  620 560]);
CV = addSub(M, 'Convector_Branch',                [ 420 600  620 800]);
PL = addSub(M, 'Plant_Hydraulic_Circuit',         [ 780  40 1040 800]);
SC = addSub(M, 'Sensors_and_Signal_Conditioning', [1220  40 1440 420]);
CB = addSub(M, 'Cabin_Thermal_Model',             [1220 480 1440 700]);
CT = addSub(M, 'HVAC_Control',                    [ 420 900  680 1300]);
SM = addSub(M, 'Safety_Manager',                  [ 860 900 1100 1300]);
DL = addSub(M, 'Results',                         [1260 880 1480 1460]);

cmdNames = {'heater_enable', 'heater_power_cmd', 'main_pump_speed_cmd', 'heating_pump_speed_cmd', ...
    'frontbox_valve_cmd', 'convector_2way_valve_cmd', 'branch_3way_valve_cmd', 'bypass_valve_cmd', ...
    'preheater_enable', 'preheater_power_cmd', 'frontbox_fan_cmd'};

% ---------------- Test_Scenarios
tsOut = {'setpoint_C', 'ambient_C', 'ignition', 'HVAC_enable', 'fault_reset', 'passengers', ...
         'solar_W', 'door_loss_W', 'valve_force_close', 'pump_capacity_factor'};
tsVar = {'scn_setpoint', 'scn_ambient', 'scn_ignition', 'scn_hvac_enable', 'scn_fault_reset', ...
         'scn_passengers', 'scn_solar', 'scn_door', 'scn_valve_close', 'scn_pump_capacity'};
addPorts(TS, {}, tsOut, 20, 400);
for k = 1:numel(tsOut)
    b = [TS '/FW_' tsOut{k}];
    addB('simulink/Sources/From Workspace', b, 'VariableName', tsVar{k}, ...
        'Position', [100 25+50*(k-1) 220 49+50*(k-1)]);
    set_param(b, 'OutputAfterFinalValue', 'Holding final value', 'Interpolate', 'on');
    ln(TS, ['FW_' tsOut{k} '/1'], [tsOut{k} '/1'], tsOut{k});
end
note(TS, sprintf('Scenario signals are generated from the\nParameters block (double-click it)'), [100 540 360 580]);

% ---------------- HVAC_Control (discrete, Ts_ctrl)
ctIn = {'cabin_temperature_setpoint_C', 'T_cabin_front_C', 'T_cabin_rear_C', 'T_HVH_out_C', ...
        'T_supply_C', 'T_return_C', 'main_flow_kg_s', 'ambient_temperature_C', 'vehicle_ignition', ...
        'HVAC_enable', 'fault_reset', 'fault_any_prev', 'valve_force_close'};
ctOut = [cmdNames, {'heating_request', 'T_cabin_feedback_C'}];
addPorts(CT, ctIn, ctOut, 20, 800);
addB('simulink/User-Defined Functions/MATLAB Function', [CT '/Controller'], 'Position', [300 30 600 680]);
setMF([CT '/Controller'], mf_control(), struct());
for k = 1:numel(ctIn), ln(CT, [ctIn{k} '/1'], sprintf('Controller/%d', k), ctIn{k}); end
for k = 1:numel(ctOut), ln(CT, sprintf('Controller/%d', k), [ctOut{k} '/1'], ctOut{k}); end
set_param(CT, 'TreatAsAtomicUnit', 'on', 'SystemSampleTime', 'Ts_ctrl');
note(CT, sprintf(['Heating request: hysteresis (on > 1.0 K error, off < 0.2 K)\n' ...
    'Heater: PI (Kp_heater, Ki_heater) + back-calculation anti-windup + 80..85 degC derating']), [300 700 800 740]);

% ---------------- Safety_Manager (discrete, Ts_ctrl)
smIn = {'ctrl_cmd', 'safety_meas', 'fault_reset', 'HVAC_enable'};
smOut = [cmdNames, {'faults', 'fault_any'}];
addPorts(SM, smIn, smOut, 20, 800);
addB('simulink/User-Defined Functions/MATLAB Function', [SM '/Safety_Logic'], 'Position', [300 30 600 680]);
setMF([SM '/Safety_Logic'], mf_safety(), struct('faults', '[10 1]'));
for k = 1:numel(smIn), ln(SM, [smIn{k} '/1'], sprintf('Safety_Logic/%d', k), smIn{k}); end
for k = 1:numel(smOut), ln(SM, sprintf('Safety_Logic/%d', k), [smOut{k} '/1'], smOut{k}); end
set_param(SM, 'TreatAsAtomicUnit', 'on', 'SystemSampleTime', 'Ts_ctrl');
note(SM, sprintf(['faults = [overtemp low_flow sensor pressure pump freeze valve cabin_ot critical any]\n' ...
    'Critical faults latch until a rising fault_reset after the condition cleared.\n' ...
    'Fault: heaters off, bypass open, pump cooldown (if pump healthy).']), [300 700 800 760]);

% ---------------- Sensors_and_Signal_Conditioning
scIn = {'T_water_K', 'p_water_Pa', 'mdot_kg_s', 'T_cabin_front_K', 'T_cabin_rear_K', 'actuator_pos'};
scOut = {'T_cabin_front_C', 'T_cabin_rear_C', 'T_HVH_out_C', 'T_supply_C', 'T_return_C', ...
         'main_flow_kg_s', 'safety_meas', 'T_water_C'};
addPorts(SC, scIn, scOut, 20, 800);
addLag(SC, 'Water_Temperature_Sensors', [120 20 200 60], 'water_sensor_tau_s', 'fluid_initial_temperature_K*ones(17,1)');
addLag(SC, 'Mass_Flow_Sensors', [120 120 200 160], 'flow_sensor_tau_s', 'zeros(5,1)');
addLag(SC, 'Interior_Temperature_Sensor_Front', [120 170 200 210], 'cabin_sensor_tau_s', 'T_cabin_initial_K + cabin_sensor_offset_front_K');
addLag(SC, 'Interior_Temperature_Sensor_Rear', [120 220 200 260], 'cabin_sensor_tau_s', 'T_cabin_initial_K + cabin_sensor_offset_rear_K');
addB('simulink/User-Defined Functions/MATLAB Function', [SC '/Conditioning'], 'Position', [350 30 600 420]);
setMF([SC '/Conditioning'], mf_conditioning(), struct('safety_meas', '[15 1]', 'T_water_C', '[17 1]'));
ln(SC, 'T_water_K/1', 'Water_Temperature_Sensors/1', 'T_water_K');
ln(SC, 'Water_Temperature_Sensors/1', 'Conditioning/1', 'T_water_meas_K');
ln(SC, 'p_water_Pa/1', 'Conditioning/2', 'p_water_Pa');
ln(SC, 'mdot_kg_s/1', 'Mass_Flow_Sensors/1', 'mdot_kg_s');
ln(SC, 'Mass_Flow_Sensors/1', 'Conditioning/3', 'mdot_meas');
ln(SC, 'T_cabin_front_K/1', 'Interior_Temperature_Sensor_Front/1', 'T_front_K');
ln(SC, 'Interior_Temperature_Sensor_Front/1', 'Conditioning/4', '');
ln(SC, 'T_cabin_rear_K/1', 'Interior_Temperature_Sensor_Rear/1', 'T_rear_K');
ln(SC, 'Interior_Temperature_Sensor_Rear/1', 'Conditioning/5', '');
ln(SC, 'actuator_pos/1', 'Conditioning/6', 'actuator_pos');
for k = 1:numel(scOut), ln(SC, sprintf('Conditioning/%d', k), [scOut{k} '/1'], scOut{k}); end
note(SC, sprintf(['T_water order: 1 pump_in 2 pump_out 3 HVH_in 4 HVH_out 5 supply 6 return 7 FB_in 8 FB_out\n' ...
    '9 CV_supply 10 CV_return 11 PH_in 12 PH_out 13 CV_L1 14 CV_L2 15 CV_R1 16 CV_R2 17 FB_mid\n' ...
    'mdot order: main, frontbox, convector, bypass, pre-heater.  T_C = T_K - 273.15']), [100 450 760 510]);

% ---------------- Cabin_Thermal_Model
cbIn = {'Q_frontbox_W', 'Q_convectors_W', 'passengers', 'solar_W', 'door_loss_W', 'ambient_C', 'Q_cooling_W'};
cbOut = {'T_cabin_air_K', 'T_structure_K', 'T_sensor_front_K', 'T_sensor_rear_K', 'Q_cabin_net_W'};
addPorts(CB, cbIn, cbOut, 20, 700);
addB('simulink/User-Defined Functions/MATLAB Function', [CB '/Cabin_Heat_Balance'], 'Position', [250 30 450 380]);
setMF([CB '/Cabin_Heat_Balance'], mf_cabin(), struct('dx', '[2 1]'));
addB('simulink/Continuous/Integrator', [CB '/Cabin_States'], ...
    'InitialCondition', '[T_cabin_initial_K; T_cabin_initial_K]', 'Position', [520 30 550 60]);
ln(CB, 'Cabin_Heat_Balance/1', 'Cabin_States/1', 'dT_dt');
ln(CB, 'Cabin_States/1', 'Cabin_Heat_Balance/1', 'x_cabin');
for k = 1:numel(cbIn), ln(CB, [cbIn{k} '/1'], sprintf('Cabin_Heat_Balance/%d', k+1), cbIn{k}); end
for k = 1:numel(cbOut), ln(CB, sprintf('Cabin_Heat_Balance/%d', k+1), [cbOut{k} '/1'], cbOut{k}); end
note(CB, sprintf(['C_air dTa/dt = Q_fb + Q_cv + Q_pass + Q_solar - UA_amb(Ta-Tamb) - Q_door - UA_as(Ta-Ts) + Q_cool\n' ...
    'C_struct dTs/dt = UA_as(Ta-Ts)    (single homogeneous zone, two sensors)']), [200 420 760 470]);

% ---------------- High_Voltage_Heater
hvIn = {'heater_enable', 'heater_power_cmd', 'T_in_K', 'T_out_K', 'mdot_kg_s'};
hvOut = {'Q_to_fluid_W', 'P_electric_W', 'interlock_active'};
addPorts(HV, hvIn, hvOut, 20, 760);
addB('simulink/User-Defined Functions/MATLAB Function', [HV '/Interlock'], 'Position', [150 30 330 260]);
setMF([HV '/Interlock'], mf_hvh(), struct());
addHeaterChain(HV, 'P_HVH_nominal_W', 'heater_efficiency');
for k = 1:numel(hvIn), ln(HV, [hvIn{k} '/1'], sprintf('Interlock/%d', k), hvIn{k}); end
ln(HV, 'Interlock/1', 'Power_Ramp/1', 'cmd_after_interlock');
ln(HV, 'Interlock/2', 'interlock_active/1', 'interlock_active');
ln(HV, 'Electric_Power/1', 'P_electric_W/1', 'P_electric_W');
ln(HV, 'Efficiency/1', 'Q_to_fluid_W/1', 'Q_to_fluid_W');
note(HV, sprintf(['Q_to_fluid = heater_efficiency * P_HVH_nominal_W * command\n' ...
    'Interlock: low flow, outlet over-temperature, NaN sensor -> command 0\n' ...
    'Rate limiter + first-order element response']), [100 300 700 360]);

% ---------------- PreHeater_Branch
phIn = {'preheater_enable', 'preheater_power_cmd', 'T_out_K', 'mdot_kg_s'};
phOut = {'Q_PH_W', 'P_electric_PH_W'};
addPorts(PH, phIn, phOut, 20, 760);
addB('simulink/User-Defined Functions/MATLAB Function', [PH '/Interlock'], 'Position', [150 30 330 220]);
setMF([PH '/Interlock'], mf_preheater(), struct());
addHeaterChain(PH, 'P_preheater_nominal_W', 'preheater_efficiency');
for k = 1:numel(phIn), ln(PH, [phIn{k} '/1'], sprintf('Interlock/%d', k), phIn{k}); end
ln(PH, 'Interlock/1', 'Power_Ramp/1', 'cmd_after_interlock');
ln(PH, 'Electric_Power/1', 'P_electric_PH_W/1', 'P_electric_PH_W');
ln(PH, 'Efficiency/1', 'Q_PH_W/1', 'Q_PH_W');

% ---------------- Frontbox_Branch (fan + 3-way valve actuators, metal thermal mass)
fbIn = {'frontbox_fan_cmd', 'frontbox_valve_cmd', 'Q_FB_air_W'};
fbOut = {'Q_FB_total_W', 'frontbox_valve_pos', 'fan_power_W', 'fan_speed'};
addPorts(FB, fbIn, fbOut, 20, 800);
addActuator(FB, 'Fan_Motor', [100 20 180 60], '1', '1', 'fan_time_constant_s');
addActuator(FB, 'ThreeWay_Valve_Actuator', [100 80 180 120], 'valve_rate_1_s', 'valve_rate_1_s', 'valve_actuator_time_constant_s');
addB('simulink/User-Defined Functions/MATLAB Function', [FB '/Fan_Power'], 'Position', [300 20 420 70]);
setMF([FB '/Fan_Power'], mf_fanpower(), struct());
addLag(FB, 'Metal_Thermal_Mass', [300 140 380 180], 'frontbox_metal_thermal_mass_J_K/frontbox_UA_W_K', 'zeros(2,1)');
addB('simulink/Math Operations/Sum of Elements', [FB '/Sum_Q'], 'Position', [450 145 480 175]);
ln(FB, 'frontbox_fan_cmd/1', 'Fan_Motor/1', 'fan_cmd');
ln(FB, 'Fan_Motor/1', 'Fan_Power/1', 'fan_speed');
ln(FB, 'Fan_Motor/1', 'fan_speed/1', '');
ln(FB, 'Fan_Power/1', 'fan_power_W/1', 'fan_power_W');
ln(FB, 'frontbox_valve_cmd/1', 'ThreeWay_Valve_Actuator/1', 'water_valve_cmd');
ln(FB, 'ThreeWay_Valve_Actuator/1', 'frontbox_valve_pos/1', 'frontbox_valve_pos');
ln(FB, 'Q_FB_air_W/1', 'Metal_Thermal_Mass/1', 'Q_from_water_W');
ln(FB, 'Metal_Thermal_Mass/1', 'Sum_Q/1', 'Q_heat_to_cabin_W');
ln(FB, 'Sum_Q/1', 'Q_FB_total_W/1', 'Q_FB_total_W');
note(FB, sprintf(['Frontbox_Driver + Frontbox_Passenger (frontbox_connection_mode = parallel | series)\n' ...
    'Water side + e-NTU air side (Q = eps*C_min*(T_water_in - T_cabin)) are solved in Plant_Hydraulic_Circuit.\n' ...
    'Here: fan motor, 3-way water valve actuator, metal thermal mass (lag C/UA), fan power P_nom*n^3.']), [100 220 800 280]);

% ---------------- Convector_Branch (heating circuit pump + valve actuators, metal mass)
cvIn = {'heating_pump_speed_cmd', 'convector_2way_valve_cmd', 'branch_3way_valve_cmd', 'Q_CV_air_W'};
cvOut = {'Q_CV_total_W', 'heating_pump_speed', 'convector_2way_pos', 'convector_3way_pos'};
addPorts(CV, cvIn, cvOut, 20, 800);
addActuator(CV, 'Heating_Pump_Motor', [100 20 180 60], 'pump_rate_1_s', 'pump_rate_1_s', 'pump_time_constant_s');
addActuator(CV, 'TwoWay_Valve_Actuator', [100 70 180 110], 'valve_rate_1_s', 'valve_rate_1_s', 'valve_actuator_time_constant_s');
addActuator(CV, 'ThreeWay_Valve_Actuator', [100 120 180 160], 'valve_rate_1_s', 'valve_rate_1_s', 'valve_actuator_time_constant_s');
addLag(CV, 'Metal_Thermal_Mass', [300 160 380 200], 'convector_metal_thermal_mass_J_K/convector_UA_each_W_K', 'zeros(6,1)');
addB('simulink/Math Operations/Sum of Elements', [CV '/Sum_Q'], 'Position', [450 165 480 195]);
ln(CV, 'heating_pump_speed_cmd/1', 'Heating_Pump_Motor/1', 'hc_pump_cmd');
ln(CV, 'Heating_Pump_Motor/1', 'heating_pump_speed/1', 'heating_pump_speed');
ln(CV, 'convector_2way_valve_cmd/1', 'TwoWay_Valve_Actuator/1', 'valve_cmd_2way');
ln(CV, 'TwoWay_Valve_Actuator/1', 'convector_2way_pos/1', 'convector_2way_pos');
ln(CV, 'branch_3way_valve_cmd/1', 'ThreeWay_Valve_Actuator/1', 'valve_cmd_3way');
ln(CV, 'ThreeWay_Valve_Actuator/1', 'convector_3way_pos/1', 'convector_3way_pos');
ln(CV, 'Q_CV_air_W/1', 'Metal_Thermal_Mass/1', 'Q_from_water_W');
ln(CV, 'Metal_Thermal_Mass/1', 'Sum_Q/1', 'Q_convectors_to_cabin_W');
ln(CV, 'Sum_Q/1', 'Q_CV_total_W/1', 'Q_CV_total_W');
note(CV, sprintf(['Convector_Front_Left -> Mid_Left -> Rear_Left  ||  Convector_Front_Right -> Mid_Right -> Rear_Right\n' ...
    'Purple circuit: Heating_Circuit_Pump -> 2-way valve -> 3-way diverting valve -> bank / bypass leg\n' ...
    'Water side + heat release solved in Plant_Hydraulic_Circuit; here: actuators + metal/body thermal mass (lag C/UA).']), [100 240 800 300]);

% ---------------- Plant_Hydraulic_Circuit
plIn = {'Q_HVH_W', 'Q_PH_W', 'main_pump_speed_cmd', 'bypass_valve_cmd', 'heating_pump_speed', ...
        'frontbox_valve_pos', 'convector_2way_pos', 'convector_3way_pos', 'pump_capacity_factor', ...
        'fan_speed', 'T_cabin_K'};
plOut = {'T_water_K', 'p_water_Pa', 'mdot_kg_s', 'Q_FB_air_W', 'Q_CV_air_W', 'T_HVH_in_K', 'T_HVH_out_K', ...
         'mdot_main', 'mdot_preheater', 'T_preheater_out_K', 'actuator_pos'};
addPorts(PL, plIn, plOut, 20, 1000);
addActuator(PL, 'Main_Pump_Actuator', [120 230 200 270], 'pump_rate_1_s', 'pump_rate_1_s', 'pump_time_constant_s');
addActuator(PL, 'Bypass_Valve_Actuator', [120 300 200 340], 'valve_rate_1_s', 'valve_rate_1_s', 'valve_actuator_time_constant_s');
addB('simulink/Signal Routing/Mux', [PL '/Mux_Actuator_Pos'], 'Inputs', '2', 'Position', [300 600 305 650]);
addB('simulink/User-Defined Functions/MATLAB Function', [PL '/Water_Circuit'], 'Position', [450 60 700 700]);
setMF([PL '/Water_Circuit'], mf_plant(), struct('dx', '[12 1]', 'T_water_K', '[17 1]', ...
    'p_water_Pa', '[17 1]', 'mdot_kg_s', '[5 1]', 'Q_FB_air_W', '[2 1]', 'Q_CV_air_W', '[6 1]'));
addB('simulink/Continuous/Integrator', [PL '/Water_Temperatures'], 'InitialCondition', 'lumped_x0', ...
    'Position', [380 20 410 50]);
ln(PL, 'main_pump_speed_cmd/1', 'Main_Pump_Actuator/1', 'main_pump_cmd');
ln(PL, 'bypass_valve_cmd/1', 'Bypass_Valve_Actuator/1', 'bypass_cmd');
ln(PL, 'Main_Pump_Actuator/1', 'Mux_Actuator_Pos/1', 'main_pump_speed');
ln(PL, 'Bypass_Valve_Actuator/1', 'Mux_Actuator_Pos/2', 'bypass_position');
ln(PL, 'Mux_Actuator_Pos/1', 'actuator_pos/1', 'actuator_pos');
ln(PL, 'Water_Circuit/1', 'Water_Temperatures/1', 'dT_dt');
ln(PL, 'Water_Temperatures/1', 'Water_Circuit/1', 'T_states_K');
plSrc = {'Q_HVH_W/1', 'Q_PH_W/1', 'Main_Pump_Actuator/1', 'pump_capacity_factor/1', 'Bypass_Valve_Actuator/1', ...
         'heating_pump_speed/1', 'frontbox_valve_pos/1', 'convector_2way_pos/1', 'convector_3way_pos/1', ...
         'fan_speed/1', 'T_cabin_K/1'};
for k = 1:numel(plSrc), ln(PL, plSrc{k}, sprintf('Water_Circuit/%d', k+1), ''); end
for k = 1:10, ln(PL, sprintf('Water_Circuit/%d', k+1), [plOut{k} '/1'], plOut{k}); end
note(PL, sprintf(['HOT-WATER CIRCUIT (lumped physical model, Simulink only)\n' ...
    'Main loop (dark red): J_return -> Water_Tank T-junction -> Air_Separator -> Main_Circulation_Pump\n' ...
    '   -> Check_Valve (cracking pressure) -> High_Voltage_Heater -> T_supply -> supply manifold\n' ...
    'Branch 1 (red/orange): 3-way valve -> Frontbox_Driver || Frontbox_Passenger (+ balancing), bypass leg\n' ...
    'Branch 2 (purple): Heating_Circuit_Pump -> 2-way valve -> 3-way valve -> convector bank (L/R chains), bypass leg\n' ...
    'Branch 3: Pre-Heater (restricted branch)  |  Main bypass (black): bypass valve + fixed restriction\n' ...
    'Pump: dp = dp0*n^2 - K*m^2 ; losses dp = (m/G)^2 ; closed valves keep leakage ; network solved by bisection.\n' ...
    'Water_Tank: pressure reference p_tank + expansion volume (return node). Fluid: 50/50 glycol, constant properties.']), ...
    [440 740 1000 900]);

% ---------------- Results (logging, scopes, displays)
dlIn = {'setpoint_C', 'T_cabin_front_C', 'T_cabin_rear_C', 'T_water_C', 'mdot_kg_s', 'safe_cmd', ...
        'Q_HVH_W', 'P_el_HVH_W', 'Q_PH_W', 'P_el_PH_W', 'Q_FB_total_W', 'Q_CV_total_W', 'fan_power_W', ...
        'actuator_pos', 'faults', 'T_cabin_air_K', 'p_water_Pa', 'heating_request', 'ctrl_cmd', ...
        'hvh_interlock', 'T_cabin_feedback_C', 'T_structure_K', 'Q_cabin_net_W'};
addPorts(DL, dlIn, {}, 20, 600);
for k = 1:numel(dlIn)
    b = [DL '/log_' dlIn{k}];
    addB('simulink/Sinks/To Workspace', b, 'VariableName', ['log_' dlIn{k}], ...
        'SaveFormat', 'Structure With Time', 'MaxDataPoints', 'inf', 'SampleTime', 'log_sample_time_s', ...
        'Position', [200 25+50*(k-1) 320 45+50*(k-1)]);
    ln(DL, [dlIn{k} '/1'], ['log_' dlIn{k} '/1'], dlIn{k});
end
% Scopes: double-click after a simulation to see the signals
addB('simulink/Math Operations/Gain', [DL '/Select_Water_T_3_to_10'], 'Gain', '[zeros(8,2) eye(8) zeros(8,7)]', ...
    'Multiplication', 'Matrix(K*u)', 'Position', [420 175 480 205]);
ln(DL, 'T_water_C/1', 'Select_Water_T_3_to_10/1', '');
scopes = {'Scope_1_Cabin_Temperatures', {'setpoint_C/1', 'T_cabin_front_C/1', 'T_cabin_rear_C/1', 'T_cabin_feedback_C/1'}, 1;
          'Scope_2_Water_Temperatures', {'Select_Water_T_3_to_10/1'}, 1;
          'Scope_3_Mass_Flows', {'mdot_kg_s/1'}, 1;
          'Scope_4_Heater_and_Cabin_Heat', {'P_el_HVH_W/1', 'Q_HVH_W/1', 'P_el_PH_W/1', 'Q_FB_total_W/1', 'Q_CV_total_W/1'}, 1;
          'Scope_5_Commands_and_Actuators', {'safe_cmd/1', 'actuator_pos/1'}, 2;
          'Scope_6_Faults', {'faults/1'}, 1};
for k = 1:size(scopes, 1)
    sb = [DL '/' scopes{k, 1}];
    nIn = numel(scopes{k, 2});
    addB('simulink/Sinks/Scope', sb, 'NumInputPorts', num2str(nIn), ...
        'Position', [700 40+150*(k-1) 760 40+150*(k-1)+20+25*nIn]);
    for j = 1:nIn
        ln(DL, scopes{k, 2}{j}, sprintf('%s/%d', scopes{k, 1}, j), '');
    end
    try
        sc = get_param(sb, 'ScopeConfiguration');
        sc.ShowLegend = true;
        if scopes{k, 3} > 1, sc.LayoutDimensions = [scopes{k, 3} 1]; end
    catch
        % older releases: default scope settings
    end
end
% Live value displays (show the value at the end of each run)
dsp = {'Display_Cabin_Temperature_C',   'T_cabin_feedback_C/1', '';
       'Display_Heater_Outlet_C',       'T_water_C/1',  '[0 0 0 1 zeros(1,13)]';
       'Display_Main_Flow_kg_s',        'mdot_kg_s/1',  '[1 0 0 0 0]';
       'Display_Bypass_Flow_kg_s',      'mdot_kg_s/1',  '[0 0 0 1 0]';
       'Display_Heater_Power_kW',       'P_el_HVH_W/1', '1e-3';
       'Display_Critical_Fault',        'faults/1',     '[zeros(1,8) 1 0]';
       'Display_Any_Fault',             'faults/1',     '[zeros(1,9) 1]'};
for k = 1:size(dsp, 1)
    y = 40 + 70*(k-1);
    db = dsp{k, 1};
    addB('simulink/Sinks/Display', [DL '/' db], 'Position', [1080 y 1200 y+30]);
    if isempty(dsp{k, 3})
        ln(DL, dsp{k, 2}, [db '/1'], '');
    else
        gb = ['Pick_' db(9:end)];
        addB('simulink/Math Operations/Gain', [DL '/' gb], 'Gain', dsp{k, 3}, ...
            'Multiplication', 'Matrix(K*u)', 'Position', [950 y 1010 y+30]);
        ln(DL, dsp{k, 2}, [gb '/1'], '');
        ln(DL, [gb '/1'], [db '/1'], '');
    end
end
% energy counters [kWh]
addB('simulink/Math Operations/Sum', [DL '/Sum_Electric_Power'], 'Inputs', '+++', 'Position', [880 560 900 620]);
ln(DL, 'P_el_HVH_W/1', 'Sum_Electric_Power/1', '');
ln(DL, 'P_el_PH_W/1', 'Sum_Electric_Power/2', '');
ln(DL, 'fan_power_W/1', 'Sum_Electric_Power/3', '');
en = {'Heater_Energy', 'P_el_HVH_W/1', 540; 'Total_HVAC_Energy', 'Sum_Electric_Power/1', 620};
for k = 1:size(en, 1)
    y = en{k, 3};
    addB('simulink/Continuous/Integrator', [DL '/Integrate_' en{k, 1}], 'Position', [950 y 980 y+30]);
    addB('simulink/Math Operations/Gain', [DL '/J_to_kWh_' en{k, 1}], 'Gain', '1/3.6e6', 'Position', [1010 y 1050 y+30]);
    addB('simulink/Sinks/Display', [DL '/Display_' en{k, 1} '_kWh'], 'Position', [1080 y 1200 y+30]);
    ln(DL, en{k, 2}, ['Integrate_' en{k, 1} '/1'], '');
    ln(DL, ['Integrate_' en{k, 1} '/1'], ['J_to_kWh_' en{k, 1} '/1'], '');
    ln(DL, ['J_to_kWh_' en{k, 1} '/1'], ['Display_' en{k, 1} '_kWh/1'], '');
end
% time-to-setpoint detector (discrete, Ts_ctrl) + Stop Simulation
addB('simulink/Sources/Clock', [DL '/Clock'], 'Position', [880 700 900 720]);
RD = addSub(DL, 'Setpoint_Reach_Detector', [950 680 1040 760]);
addPorts(RD, {'T_cabin_feedback_C', 'setpoint_C', 'time_s'}, {'reached', 'time_to_setpoint_min', 'stop_sim'}, 20, 500);
addB('simulink/User-Defined Functions/MATLAB Function', [RD '/Detector'], 'Position', [200 30 380 180]);
setMF([RD '/Detector'], mf_reach(), struct());
ln(RD, 'T_cabin_feedback_C/1', 'Detector/1', '');
ln(RD, 'setpoint_C/1', 'Detector/2', '');
ln(RD, 'time_s/1', 'Detector/3', '');
ln(RD, 'Detector/1', 'reached/1', '');
ln(RD, 'Detector/2', 'time_to_setpoint_min/1', '');
ln(RD, 'Detector/3', 'stop_sim/1', '');
set_param(RD, 'TreatAsAtomicUnit', 'on', 'SystemSampleTime', 'Ts_ctrl');
ln(DL, 'T_cabin_feedback_C/1', 'Setpoint_Reach_Detector/1', '');
ln(DL, 'setpoint_C/1', 'Setpoint_Reach_Detector/2', '');
ln(DL, 'Clock/1', 'Setpoint_Reach_Detector/3', 'time_s');
addB('simulink/Sinks/Display', [DL '/Display_Setpoint_Reached'], 'Position', [1080 700 1200 730]);
addB('simulink/Sinks/Display', [DL '/Display_Time_to_Setpoint_min'], 'Position', [1080 760 1200 790]);
addB('simulink/Sinks/Stop Simulation', [DL '/Stop_When_Setpoint_Reached'], 'Position', [1100 820 1130 850]);
ln(DL, 'Setpoint_Reach_Detector/1', 'Display_Setpoint_Reached/1', 'reached');
ln(DL, 'Setpoint_Reach_Detector/2', 'Display_Time_to_Setpoint_min/1', 'time_to_setpoint_min');
ln(DL, 'Setpoint_Reach_Detector/3', 'Stop_When_Setpoint_Reached/1', 'stop_sim');
note(DL, sprintf(['RESULTS\n' ...
    'Displays (right): cabin temperature, heater outlet, main / bypass flow, heater power, energy, faults,\n' ...
    'TIME TO SETPOINT [min after HVAC on] (-1 = not reached yet); simulation stops there if enabled in Parameters.\n' ...
    'Scopes (middle, double-click): 1 cabin [degC] | 2 water: HVH in/out, supply, return, FB in/out, CV supply/return [degC]\n' ...
    '3 flow [kg/s]: main, frontbox, convector, bypass, pre-heater | 4 [W]: HVH electric, HVH heat, PH electric, FB heat, CV heat\n' ...
    '5 commands (top) + actuator positions (bottom) | 6 fault flags. To Workspace blocks (left) log everything for the script.']), ...
    [380 960 1200 1060]);

% ---------------- top-level wiring
addB('simulink/Sources/Constant', [M '/Q_Cooling_W'], 'Value', '0', 'Position', [1100 640 1140 660]);
addB('simulink/Signal Routing/Mux', [M '/Mux_Ctrl_Cmd'], 'Inputs', '11', 'Position', [760 900 765 1300]);
addB('simulink/Signal Routing/Mux', [M '/Mux_Safe_Cmd'], 'Inputs', '11', 'Position', [1160 900 1165 1300]);
addB('simulink/Signal Routing/Mux', [M '/Mux_Actuator_Pos'], 'Inputs', '5', 'Position', [1120 330 1125 430]);
addB('simulink/Discrete/Unit Delay', [M '/Fault_Delay'], 'SampleTime', 'Ts_ctrl', 'Position', [760 1340 790 1370]);
n = @(b) strrep(b, [M '/'], '');
f = @(b, k) sprintf('%s/%d', n(b), k);
w = @(s, d, nm) ln(M, s, d, nm);
% plant inputs
w(f(HV, 1), f(PL, 1), 'Q_HVH_W');               w(f(PH, 1), f(PL, 2), 'Q_PH_W');
w(f(SM, 3), f(PL, 3), 'main_pump_speed_cmd');   w(f(SM, 8), f(PL, 4), 'bypass_valve_cmd');
w(f(CV, 2), f(PL, 5), 'heating_pump_speed');    w(f(FB, 2), f(PL, 6), 'frontbox_valve_pos');
w(f(CV, 3), f(PL, 7), 'convector_2way_pos');    w(f(CV, 4), f(PL, 8), 'convector_3way_pos');
w(f(TS, 10), f(PL, 9), 'pump_capacity_factor'); w(f(FB, 4), f(PL, 10), 'fan_speed');
w(f(CB, 1), f(PL, 11), 'T_cabin_air_K');
% heaters
w(f(SM, 1), f(HV, 1), 'heater_enable');         w(f(SM, 2), f(HV, 2), 'heater_power_cmd');
w(f(PL, 6), f(HV, 3), 'T_HVH_in_K');            w(f(PL, 7), f(HV, 4), 'T_HVH_out_K');
w(f(PL, 8), f(HV, 5), 'mdot_main');
w(f(SM, 9), f(PH, 1), 'preheater_enable');      w(f(SM, 10), f(PH, 2), 'preheater_power_cmd');
w(f(PL, 10), f(PH, 3), 'T_preheater_out_K');    w(f(PL, 9), f(PH, 4), 'mdot_preheater');
% consumers
w(f(SM, 11), f(FB, 1), 'frontbox_fan_cmd');     w(f(SM, 5), f(FB, 2), 'frontbox_valve_cmd');
w(f(PL, 4), f(FB, 3), 'Q_FB_air_W');
w(f(SM, 4), f(CV, 1), 'heating_pump_speed_cmd'); w(f(SM, 6), f(CV, 2), 'convector_2way_valve_cmd');
w(f(SM, 7), f(CV, 3), 'branch_3way_valve_cmd'); w(f(PL, 5), f(CV, 4), 'Q_CV_air_W');
% cabin
w(f(FB, 1), f(CB, 1), 'Q_FB_total_W');          w(f(CV, 1), f(CB, 2), 'Q_CV_total_W');
w(f(TS, 6), f(CB, 3), 'passengers');            w(f(TS, 7), f(CB, 4), 'solar_W');
w(f(TS, 8), f(CB, 5), 'door_loss_W');           w(f(TS, 2), f(CB, 6), 'ambient_C');
w('Q_Cooling_W/1', f(CB, 7), 'Q_cooling_W');
% sensors
w(f(PL, 1), f(SC, 1), 'T_water_K');             w(f(PL, 2), f(SC, 2), 'p_water_Pa');
w(f(PL, 3), f(SC, 3), 'mdot_kg_s');
w(f(CB, 3), f(SC, 4), 'T_sensor_front_K');      w(f(CB, 4), f(SC, 5), 'T_sensor_rear_K');
w(f(PL, 11), 'Mux_Actuator_Pos/1', 'pump_bypass_pos');
w(f(CV, 2), 'Mux_Actuator_Pos/2', '');          w(f(FB, 2), 'Mux_Actuator_Pos/3', '');
w(f(CV, 3), 'Mux_Actuator_Pos/4', '');          w(f(CV, 4), 'Mux_Actuator_Pos/5', '');
w('Mux_Actuator_Pos/1', f(SC, 6), 'actuator_pos');
% control (fault feedback through a unit delay)
w(f(SM, 13), 'Fault_Delay/1', 'fault_any');
ctSrc = {f(TS, 1), f(SC, 1), f(SC, 2), f(SC, 3), f(SC, 4), f(SC, 5), f(SC, 6), f(TS, 2), ...
         f(TS, 3), f(TS, 4), f(TS, 5), 'Fault_Delay/1', f(TS, 9)};
for k = 1:numel(ctSrc), w(ctSrc{k}, f(CT, k), ''); end
for k = 1:11, w(f(CT, k), sprintf('Mux_Ctrl_Cmd/%d', k), cmdNames{k}); end
w('Mux_Ctrl_Cmd/1', f(SM, 1), 'ctrl_cmd');      w(f(SC, 7), f(SM, 2), 'safety_meas');
w(f(TS, 5), f(SM, 3), '');                      w(f(TS, 4), f(SM, 4), '');
for k = 1:11, w(f(SM, k), sprintf('Mux_Safe_Cmd/%d', k), ''); end
% logging
dlSrc = {f(TS, 1), f(SC, 1), f(SC, 2), f(SC, 8), f(PL, 3), 'Mux_Safe_Cmd/1', f(HV, 1), f(HV, 2), ...
         f(PH, 1), f(PH, 2), f(FB, 1), f(CV, 1), f(FB, 3), 'Mux_Actuator_Pos/1', f(SM, 12), f(CB, 1), ...
         f(PL, 2), f(CT, 12), 'Mux_Ctrl_Cmd/1', f(HV, 3), f(CT, 13), f(CB, 2), f(CB, 5)};
for k = 1:numel(dlSrc), w(dlSrc{k}, f(DL, k), ''); end
% ---------------- colours (line colour follows the source block colour)
colorBlocks({HV, PH, PL}, '[0.55 0 0]', '[1 0.88 0.88]');                % dark red: main hot supply
colorBlocks({FB}, '[0.9 0 0]', '[1 0.92 0.85]');                         % red / orange: consumers
colorBlocks({CV}, '[0.5 0 0.6]', '[0.95 0.9 1]');                        % purple: heating circuit
colorBlocks({[PL '/Bypass_Valve_Actuator']}, 'black', '[0.9 0.9 0.9]');  % black: bypass
colorBlocks({[PL '/Main_Pump_Actuator'], [PL '/Water_Circuit']}, '[0.55 0 0]', '');
colorBlocks({SC, CB}, '[0 0.3 0.6]', '[0.88 0.95 1]');
colorBlocks({CT, SM}, '[0 0.45 0]', '[0.9 1 0.9]');
colorBlocks({TS, DL}, '[0.3 0.3 0.3]', '[0.95 0.95 0.95]');
note(M, sprintf(['eCoach HVAC hot-water circuit (Simulink only, lumped physical model)\n' ...
    'Dark red: main hot supply | Red: hot supply to consumers | Orange: hot return | Dark orange: main return\n' ...
    'Purple: heating (convector) circuit | Black: minimum-flow bypass | Blue: sensors / cabin | Green: control + safety\n' ...
    'PARAMETERS: double-click the yellow Parameters block (top left)  |  RESULTS: open the Results block  |  then press Run']), [40 1500 1300 1580]);

% ---------------- save + compile
save_system(M, slxFile);
op = findOpenPorts(M);
if isempty(op)
    fprintf('Open-port check: no unconnected ports\n');
else
    fprintf(2, 'Unconnected ports:\n'); fprintf(2, '   %s\n', op{:});
end
applyParams(M);
set_param(M, 'SimulationCommand', 'update');
save_system(M);
fprintf('Model built, compiled and saved: %s\n', slxFile);
end

function addHeaterChain(sys, PnomExpr, effExpr)
% Rate limiter -> first-order element response -> electric power -> heat.
addB('simulink/Discontinuities/Rate Limiter', [sys '/Power_Ramp'], ...
    'RisingSlewLimit', 'heater_rate_up_1_s', 'FallingSlewLimit', '-heater_rate_down_1_s', ...
    'Position', [380 40 410 70]);
addLag(sys, 'Element_Response', [450 35 520 75], 'heater_time_constant_s', '0');
addB('simulink/Math Operations/Gain', [sys '/Electric_Power'], 'Gain', PnomExpr, 'Position', [560 75 610 105]);
addB('simulink/Math Operations/Gain', [sys '/Efficiency'], 'Gain', effExpr, 'Position', [640 25 680 55]);
ln(sys, 'Power_Ramp/1', 'Element_Response/1', '');
ln(sys, 'Element_Response/1', 'Electric_Power/1', 'command_actual');
ln(sys, 'Electric_Power/1', 'Efficiency/1', '');
end


%% =========================================================================
%%                           BUILD HELPERS
%% =========================================================================
function sys = addSub(parent, name, pos)
sys = [parent '/' name];
if getSimulinkBlockHandle(sys) ~= -1
    error('eCoach:build', 'Block already exists: %s', sys);
end
add_block('built-in/Subsystem', sys, 'Position', pos);
end

function h = addB(src, dst, varargin)
if getSimulinkBlockHandle(dst) ~= -1
    error('eCoach:build', 'Block already exists: %s', dst);
end
try
    h = add_block(src, dst, varargin{:});
catch ME
    error('eCoach:build', 'add_block failed: %s -> %s\n  %s', src, dst, ME.message);
end
end

function addPorts(sub, inNames, outNames, xIn, xOut)
for k = 1:numel(inNames)
    addB('simulink/Sources/In1', [sub '/' inNames{k}], 'Port', num2str(k), ...
        'Position', [xIn 30+50*(k-1) xIn+30 44+50*(k-1)]);
end
for k = 1:numel(outNames)
    addB('simulink/Sinks/Out1', [sub '/' outNames{k}], 'Port', num2str(k), ...
        'Position', [xOut 30+50*(k-1) xOut+30 44+50*(k-1)]);
end
end

function ln(sys, src, dst, sigName)
% Connects 'Block/outPort' -> 'Block/inPort' inside sys (no duplicates).
[sBlk, sPort] = splitPort(src);
[dBlk, dPort] = splitPort(dst);
phS = get_param([sys '/' sBlk], 'PortHandles');
phD = get_param([sys '/' dBlk], 'PortHandles');
if sPort > numel(phS.Outport)
    error('eCoach:line', '%s/%s has %d outputs, requested output %d', sys, sBlk, numel(phS.Outport), sPort);
end
if dPort > numel(phD.Inport)
    error('eCoach:line', '%s/%s has %d inputs, requested input %d', sys, dBlk, numel(phD.Inport), dPort);
end
if get_param(phD.Inport(dPort), 'Line') ~= -1
    error('eCoach:line', 'Input already connected: %s/%s', sys, dst);
end
firstLine = get_param(phS.Outport(sPort), 'Line') == -1;
try
    lh = add_line(sys, phS.Outport(sPort), phD.Inport(dPort), 'autorouting', 'on');
catch
    try
        lh = add_line(sys, phS.Outport(sPort), phD.Inport(dPort));
    catch ME
        error('eCoach:line', 'add_line failed in %s: %s -> %s\n  %s', sys, src, dst, ME.message);
    end
end
if firstLine && ~isempty(sigName)
    set_param(lh, 'Name', sigName);
end
end

function [blk, port] = splitPort(s)
k = find(s == '/', 1, 'last');
blk = s(1:k-1);
port = str2double(s(k+1:end));
end

function setMF(blkPath, code, outSizes)
% Writes the code of a MATLAB Function block, makes 'hvacP' a parameter and
% declares the size of every output (outputs not listed are scalar).
rt = sfroot;
ch = rt.find('-isa', 'Stateflow.EMChart', 'Path', blkPath);
if isempty(ch)
    error('eCoach:mfun', 'MATLAB Function chart not found: %s', blkPath);
end
ch.Script = code;
d = ch.find('-isa', 'Stateflow.Data', 'Name', 'hvacP');
if isempty(d)
    error('eCoach:mfun', 'hvacP not found in %s', blkPath);
end
d.Scope = 'Parameter';
outs = ch.find('-isa', 'Stateflow.Data', 'Scope', 'Output');
for k = 1:numel(outs)
    nm = outs(k).Name;
    if isfield(outSizes, nm), sz = outSizes.(nm); else, sz = '1'; end
    outs(k).Props.Array.Size = sz;
    outs(k).DataType = 'double';
end
names = fieldnames(outSizes);
for k = 1:numel(names)
    if isempty(ch.find('-isa', 'Stateflow.Data', 'Scope', 'Output', 'Name', names{k}))
        error('eCoach:mfun', 'Unknown output %s in %s', names{k}, blkPath);
    end
end
end

function addLag(sys, name, pos, tauExpr, x0Expr)
% First-order lag y' = (u - y)/tau, vector capable, no direct feedthrough.
sub = addSub(sys, name, pos);
addB('simulink/Sources/In1', [sub '/u'], 'Position', [20 40 50 54]);
addB('simulink/Math Operations/Sum', [sub '/err'], 'Inputs', '+-', 'Position', [90 35 110 60]);
addB('simulink/Math Operations/Gain', [sub '/inv_tau'], 'Gain', sprintf('1/(%s)', tauExpr), 'Position', [140 32 180 62]);
addB('simulink/Continuous/Integrator', [sub '/state'], 'InitialCondition', x0Expr, 'Position', [220 32 250 62]);
addB('simulink/Sinks/Out1', [sub '/y'], 'Position', [300 40 330 54]);
ln(sub, 'u/1', 'err/1', '');
ln(sub, 'err/1', 'inv_tau/1', '');
ln(sub, 'inv_tau/1', 'state/1', '');
ln(sub, 'state/1', 'y/1', '');
ln(sub, 'state/1', 'err/2', '');
end

function addActuator(sys, name, pos, rateUpExpr, rateDownExpr, tauExpr)
% Saturation [0,1] -> Rate Limiter -> first-order actuator dynamics.
sub = addSub(sys, name, pos);
addB('simulink/Sources/In1', [sub '/cmd'], 'Position', [20 40 50 54]);
addB('simulink/Discontinuities/Saturation', [sub '/sat_0_1'], 'UpperLimit', '1', 'LowerLimit', '0', ...
    'Position', [80 32 110 62]);
addB('simulink/Discontinuities/Rate Limiter', [sub '/rate_limit'], 'RisingSlewLimit', rateUpExpr, ...
    'FallingSlewLimit', ['-(' rateDownExpr ')'], 'Position', [140 32 170 62]);
addLag(sub, 'actuator_lag', [200 30 260 64], tauExpr, '0');
addB('simulink/Sinks/Out1', [sub '/position'], 'Position', [300 40 330 54]);
ln(sub, 'cmd/1', 'sat_0_1/1', '');
ln(sub, 'sat_0_1/1', 'rate_limit/1', '');
ln(sub, 'rate_limit/1', 'actuator_lag/1', '');
ln(sub, 'actuator_lag/1', 'position/1', '');
end

function note(sys, txt, pos)
try
    a = Simulink.Annotation([sys '/eCoach_note']);
    a.Text = txt;
    a.Position = pos;
catch ME
    warning('eCoach:note', 'Annotation not added in %s: %s', sys, ME.message);
end
end

function colorBlocks(blocks, fg, bg)
for i = 1:numel(blocks)
    set_param(blocks{i}, 'ForegroundColor', fg);
    if ~isempty(bg), set_param(blocks{i}, 'BackgroundColor', bg); end
end
end

function op = findOpenPorts(sys)
op = {};
blks = find_system(sys, 'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'block');
for i = 1:numel(blks)
    if strcmp(blks{i}, sys), continue; end
    h = get_param(blks{i}, 'PortHandles');
    for k = 1:numel(h.Inport)
        if get_param(h.Inport(k), 'Line') == -1, op{end+1} = sprintf('%s : input %d', blks{i}, k); end %#ok<AGROW>
    end
    for k = 1:numel(h.Outport)
        if get_param(h.Outport(k), 'Line') == -1, op{end+1} = sprintf('%s : output %d', blks{i}, k); end %#ok<AGROW>
    end
end
end


%% =========================================================================
%%                      MATLAB FUNCTION BLOCK CODE
%% =========================================================================
function code = mf_control()
code = strjoin({
'function [heater_enable, heater_power_cmd, main_pump_speed_cmd, heating_pump_speed_cmd, frontbox_valve_cmd, convector_2way_valve_cmd, branch_3way_valve_cmd, bypass_valve_cmd, preheater_enable, preheater_power_cmd, frontbox_fan_cmd, heating_request, T_cabin_feedback_C] = hvac_control(cabin_temperature_setpoint_C, T_cabin_front_C, T_cabin_rear_C, T_HVH_out_C, T_supply_C, T_return_C, main_flow_kg_s, ambient_temperature_C, vehicle_ignition, HVAC_enable, fault_reset, fault_any_prev, valve_force_close, hvacP)'
'% Discrete HVAC supervisory controller (sample time Ts_ctrl).'
'persistent integ req postrun sat_t cold'
'if isempty(integ)'
'    integ = 0; req = 0; postrun = 0; sat_t = 0; cold = 0;'
'end'
'Ts = hvacP.Ts_ctrl;'
'Tfb = 0.5*(T_cabin_front_C + T_cabin_rear_C);'
'if ~isfinite(Tfb), Tfb = cabin_temperature_setpoint_C; end'
'T_cabin_feedback_C = Tfb;'
'on = (vehicle_ignition > 0.5) && (HVAC_enable > 0.5);'
'e = cabin_temperature_setpoint_C - Tfb;'
'% heating request with hysteresis'
'if on'
'    if e > hvacP.hyst_on_C'
'        req = 1;'
'    elseif e < hvacP.hyst_off_C'
'        req = 0;'
'    end'
'else'
'    req = 0;'
'end'
'hr = req > 0.5;'
'% PI with back-calculation anti-windup'
'if hr && fault_any_prev < 0.5'
'    u_raw = hvacP.Kp_heater*e + integ;'
'    u_pi = min(max(u_raw, 0), 1);'
'    integ = integ + Ts*(hvacP.Ki_heater*e + (u_pi - u_raw)/hvacP.Tt_antiwindup);'
'else'
'    u_pi = 0;'
'    integ = 0;'
'end'
'if fault_reset > 0.5, integ = 0; end'
'% heater outlet temperature override (linear derating)'
'Tout = T_HVH_out_C;'
'if ~isfinite(Tout), Tout = 1e3; end'
'der = (hvacP.T_HVH_derate_end_C - Tout)/(hvacP.T_HVH_derate_end_C - hvacP.T_HVH_derate_start_C);'
'u_h = u_pi*min(max(der, 0), 1);'
'% main pump'
'dTsr = T_supply_C - T_return_C;'
'if ~isfinite(dTsr), dTsr = 0; end'
'if hr || u_h > 0.01'
'    postrun = hvacP.pump_postrun_s;'
'else'
'    postrun = max(postrun - Ts, 0);'
'end'
'mflow = main_flow_kg_s;'
'if ~isfinite(mflow), mflow = 0; end'
'if on && (hr || postrun > 0)'
'    pump = hvacP.pump_min_speed + (1 - hvacP.pump_min_speed)*max(u_h, min(max(dTsr/hvacP.dT_sr_full_speed_C, 0), 1));'
'    if u_h > 0.01 && mflow < hvacP.mdot_boost_threshold_kg_s, pump = 1; end'
'else'
'    pump = 0;'
'end'
'% consumer valves'
'% opening follows the larger of the temperature error band and the PI demand'
'md = max(min(max(e/hvacP.valve_mod_band_C, 0), 1), u_pi);'
'if hr'
'    fbv = max(md, hvacP.valve_min_open_heating);'
'    cv3 = max(md, hvacP.valve_min_open_heating);'
'    cv2 = hvacP.cv2_min_open + (1 - hvacP.cv2_min_open)*md;'
'else'
'    fbv = 0; cv3 = 0; cv2 = 0;'
'end'
'if valve_force_close > 0.5'
'    fbv = 0; cv3 = 0; cv2 = 0;'
'end'
'byp = max(hvacP.bypass_min_open, 1 - max(fbv, cv2*cv3));'
'if u_h > 0.01 && mflow < hvacP.mdot_boost_threshold_kg_s, byp = 1; end'
'% heating circuit pump'
'if on && hr && cv2 > 0.05'
'    hc = max(hvacP.hc_pump_min_speed, md);'
'else'
'    hc = 0;'
'end'
'% frontbox fan'
'Tsup = T_supply_C;'
'if ~isfinite(Tsup), Tsup = -100; end'
'if hr && fbv > 0.05 && Tsup > Tfb + hvacP.fan_water_dT_min_C'
'    fan = max(hvacP.fan_min_cmd, min(max(e/hvacP.fan_band_C, 0), 1));'
'else'
'    fan = 0;'
'end'
'% pre-heater'
'if u_h >= 0.98'
'    sat_t = sat_t + Ts;'
'else'
'    sat_t = 0;'
'end'
'ph = 0;'
'Tret = T_return_C;'
'if ~isfinite(Tret), Tret = 0; end'
'if on && fault_any_prev < 0.5 && pump > 0.2'
'    if hvacP.preheater_mode_id == 1'
'        if hr && (ambient_temperature_C < hvacP.preheater_ambient_on_C || sat_t > hvacP.preheater_sat_delay_s)'
'            ph = 1;'
'        end'
'    elseif hvacP.preheater_mode_id == 2'
'        if (Tret < hvacP.preheater_cold_on_C || Tret < hvacP.T_heater_min_enable_C) && ambient_temperature_C < hvacP.preheater_cold_ambient_C'
'            cold = 1;'
'        elseif Tret > hvacP.preheater_cold_off_C'
'            cold = 0;'
'        end'
'        ph = cold;'
'    end'
'end'
'if ~on, cold = 0; end'
'% outputs'
'h_en = double(on && hr && u_h > 0.005 && pump > 0.2 && fault_any_prev < 0.5);'
'heater_enable = h_en;'
'heater_power_cmd = u_h*h_en;'
'main_pump_speed_cmd = pump;'
'heating_pump_speed_cmd = hc;'
'frontbox_valve_cmd = fbv;'
'convector_2way_valve_cmd = cv2;'
'branch_3way_valve_cmd = cv3;'
'bypass_valve_cmd = byp;'
'preheater_enable = ph;'
'preheater_power_cmd = ph;'
'frontbox_fan_cmd = fan;'
'heating_request = double(hr);'
'end'
}, newline);
end

function code = mf_safety()
code = strjoin({
'function [heater_enable, heater_power_cmd, main_pump_speed_cmd, heating_pump_speed_cmd, frontbox_valve_cmd, convector_2way_valve_cmd, branch_3way_valve_cmd, bypass_valve_cmd, preheater_enable, preheater_power_cmd, frontbox_fan_cmd, faults, fault_any] = safety_manager(cmd_in, meas_in, fault_reset, HVAC_enable, hvacP)'
'% faults = [overtemp low_flow sensor pressure pump freeze valve cabin_ot critical any]'
'persistent latch t_ot t_lf t_pr t_pu t_va pump_on cool reset_prev crit_prev out_prev'
'if isempty(latch)'
'    latch = zeros(5, 1); t_ot = 0; t_lf = 0; t_pr = 0; t_pu = 0; t_va = 0;'
'    pump_on = 0; cool = 0; reset_prev = 0; crit_prev = 0; out_prev = zeros(11, 1);'
'end'
'cmd = zeros(11, 1);'
'for k = 1:11, cmd(k) = cmd_in(k); end'
'meas = zeros(15, 1);'
'for k = 1:15, meas(k) = meas_in(k); end'
'Ts = hvacP.Ts_ctrl;'
'Tout = meas(1); Tin = meas(2); Tret = meas(4); mflow = meas(5);'
'p_in = meas(6); p_out = meas(7); p_sup = meas(8); Tcab = meas(9);'
'pos = meas(10:13); sensor_ok = meas(15);'
'% arming timer: pump commanded on'
'if cmd(3) > 0.2'
'    pump_on = pump_on + Ts;'
'else'
'    pump_on = 0;'
'end'
'armed = pump_on > hvacP.lowflow_arm_s;'
'bad_sensor = (sensor_ok < 0.5) || any(~isfinite(meas));'
'if ~bad_sensor && Tout > hvacP.T_heater_max_C, t_ot = t_ot + Ts; else, t_ot = 0; end'
'% low flow: evaluated whenever the main pump is commanded on (after arming time)'
'if ~bad_sensor && armed && mflow < hvacP.mdot_low_flow_kg_s, t_lf = t_lf + Ts; else, t_lf = 0; end'
'if ~bad_sensor && max(p_out, p_sup) > hvacP.p_max_Pa, t_pr = t_pr + Ts; else, t_pr = 0; end'
'dp_min = hvacP.pump_fault_dp_frac*hvacP.pump_dp_nominal_Pa*cmd(3)^2;'
'if ~bad_sensor && armed && cmd(3) > 0.5 && (p_out - p_in) < dp_min, t_pu = t_pu + Ts; else, t_pu = 0; end'
'% valve command / position mismatch (commands actually sent last sample)'
'mis = max(abs(out_prev([5 6 7 8]) - pos));'
'if mis > hvacP.valve_mismatch_tol, t_va = t_va + Ts; else, t_va = 0; end'
'cond = [t_ot > hvacP.overtemp_debounce_s; t_lf > hvacP.lowflow_debounce_s; bad_sensor; t_pr > hvacP.pressure_debounce_s; t_pu > hvacP.pump_fault_debounce_s];'
'% latch, reset on rising edge only when the condition has cleared'
'rise = (fault_reset > 0.5) && (reset_prev < 0.5);'
'reset_prev = fault_reset;'
'for k = 1:5'
'    if cond(k)'
'        latch(k) = 1;'
'    elseif rise'
'        latch(k) = 0;'
'    end'
'end'
'f_freeze = (~bad_sensor) && (min(Tret, Tin) < hvacP.freeze_risk_C);'
'f_valve = t_va > hvacP.valve_mismatch_time_s;'
'f_cabot = (~bad_sensor) && (Tcab > hvacP.cabin_overtemp_C);'
'critical = any(latch > 0.5);'
'out = cmd;'
'if critical || f_cabot || HVAC_enable < 0.5'
'    out(1) = 0; out(2) = 0; out(9) = 0; out(10) = 0;'
'end'
'if critical'
'    if crit_prev < 0.5, cool = hvacP.cooldown_s; end'
'    out(8) = 1;'
'    pump_safe = (latch(4) < 0.5) && (latch(5) < 0.5);'
'    if pump_safe && cool > 0'
'        out(3) = max(cmd(3), hvacP.cooldown_speed);'
'        cool = max(cool - Ts, 0);'
'    else'
'        out(3) = 0;'
'    end'
'end'
'crit_prev = double(critical);'
'if f_freeze && latch(5) < 0.5, out(3) = max(out(3), hvacP.freeze_pump_speed); end'
'out_prev = out;'
'heater_enable = out(1); heater_power_cmd = out(2); main_pump_speed_cmd = out(3);'
'heating_pump_speed_cmd = out(4); frontbox_valve_cmd = out(5); convector_2way_valve_cmd = out(6);'
'branch_3way_valve_cmd = out(7); bypass_valve_cmd = out(8); preheater_enable = out(9);'
'preheater_power_cmd = out(10); frontbox_fan_cmd = out(11);'
'anyf = critical || f_freeze || f_valve || f_cabot;'
'faults = [latch; double(f_freeze); double(f_valve); double(f_cabot); double(critical); double(anyf)];'
'fault_any = double(anyf);'
'end'
}, newline);
end

function code = mf_conditioning()
code = strjoin({
'function [T_cabin_front_C, T_cabin_rear_C, T_HVH_out_C, T_supply_C, T_return_C, main_flow_kg_s, safety_meas, T_water_C] = signal_conditioning(T_water_K, p_water_Pa, mdot_kg_s, T_front_K, T_rear_K, act_pos, hvacP)'
'% act_pos = [main_pump bypass hc_pump fb_valve cv_2way cv_3way]'
'T_water_C = zeros(17, 1);'
'for k = 1:17, T_water_C(k) = T_water_K(k) - 273.15; end'
'T_cabin_front_C = T_front_K - 273.15;'
'T_cabin_rear_C = T_rear_K - 273.15;'
'T_HVH_out_C = T_water_C(4); T_supply_C = T_water_C(5); T_return_C = T_water_C(6);'
'main_flow_kg_s = mdot_kg_s(1);'
'ok = all(isfinite(T_water_K)) && all(T_water_K > hvacP.sensor_T_min_K) && all(T_water_K < hvacP.sensor_T_max_K) && isfinite(T_front_K) && isfinite(T_rear_K) && all(isfinite(mdot_kg_s)) && all(isfinite(p_water_Pa)) && mdot_kg_s(1) > -0.5 && mdot_kg_s(1) < 5;'
'safety_meas = [T_water_C(4); T_water_C(3); T_water_C(5); T_water_C(6); mdot_kg_s(1); p_water_Pa(1); p_water_Pa(2); p_water_Pa(5); 0.5*(T_cabin_front_C + T_cabin_rear_C); act_pos(4); act_pos(5); act_pos(6); act_pos(2); act_pos(1); double(ok)];'
'end'
}, newline);
end

function code = mf_cabin()
code = strjoin({
'function [dx, T_air_K, T_struct_K, T_sensor_front_K, T_sensor_rear_K, Q_net_W] = cabin_thermal(x, Q_frontbox_W, Q_convectors_W, passengers, solar_W, door_loss_W, ambient_C, Q_cooling_W, hvacP)'
'% x = [T_cabin_air; T_cabin_structure] (K)'
'Ta = x(1); Ts = x(2); Tamb = ambient_C + 273.15;'
'Q_pass = passengers*hvacP.q_person;'
'Q_amb = hvacP.UA_amb*(Ta - Tamb);'
'Q_as = hvacP.UA_as*(Ta - Ts);'
'Q_net_W = Q_frontbox_W + Q_convectors_W + Q_pass + solar_W - Q_amb - door_loss_W + Q_cooling_W;'
'dx = [(Q_net_W - Q_as)/hvacP.C_air; Q_as/hvacP.C_struct];'
'T_air_K = Ta;'
'T_struct_K = Ts;'
'T_sensor_front_K = Ta + hvacP.off_front;'
'T_sensor_rear_K = Ta + hvacP.off_rear;'
'end'
}, newline);
end

function code = mf_hvh()
code = strjoin({
'function [cmd_eff, interlock_active] = hvh_interlock(heater_enable, heater_power_cmd, T_in_K, T_out_K, mdot_kg_s, hvacP)'
'% Instantaneous hardware interlock of the High Voltage Heater.'
'bad = ~isfinite(T_in_K) || ~isfinite(T_out_K) || ~isfinite(mdot_kg_s);'
'lock = bad || (mdot_kg_s < hvacP.hvh_min_flow_kg_s) || (T_out_K > hvacP.T_heater_max_K) || (heater_enable < 0.5);'
'interlock_active = double(lock && heater_enable > 0.5);'
'if lock'
'    cmd_eff = 0;'
'else'
'    cmd_eff = min(max(heater_power_cmd, 0), 1);'
'end'
'end'
}, newline);
end

function code = mf_preheater()
code = strjoin({
'function cmd_eff = preheater_interlock(preheater_enable, preheater_power_cmd, T_out_K, mdot_kg_s, hvacP)'
'bad = ~isfinite(T_out_K) || ~isfinite(mdot_kg_s);'
'lock = bad || (mdot_kg_s < 0.2*hvacP.hvh_min_flow_kg_s) || (T_out_K > hvacP.T_heater_max_K) || (preheater_enable < 0.5);'
'if lock'
'    cmd_eff = 0;'
'else'
'    cmd_eff = min(max(preheater_power_cmd, 0), 1);'
'end'
'end'
}, newline);
end

function code = mf_fanpower()
code = strjoin({
'function fan_power_W = fan_power(fan, hvacP)'
'% Frontbox fan electrical power (fan laws): P = P_nom * n^3'
'fan_power_W = hvacP.frontbox_fan_nominal_power_W*min(max(fan, 0), 1)^3;'
'end'
}, newline);
end

function code = mf_reach()
code = strjoin({
'function [reached, time_to_setpoint_min, stop_sim] = setpoint_reach(T_fb_C, setpoint_C, t, hvacP)'
'% Latches the first time the cabin feedback reaches setpoint - tolerance after HVAC on.'
'persistent latched t_hit'
'if isempty(latched)'
'    latched = 0; t_hit = -1;'
'end'
'if latched < 0.5 && t > hvacP.t_hvac_on && T_fb_C >= setpoint_C - hvacP.reach_tol_K'
'    latched = 1;'
'    t_hit = (t - hvacP.t_hvac_on)/60;'
'end'
'reached = latched;'
'time_to_setpoint_min = t_hit;'
'stop_sim = double(latched > 0.5 && hvacP.stop_at_setpoint > 0.5);'
'end'
}, newline);
end

function code = mf_plant()
code = strjoin({
'function [dx, T_water_K, p_water_Pa, mdot_kg_s, Q_FB_air_W, Q_CV_air_W, T_HVH_in_K, T_HVH_out_K, mdot_main, mdot_ph, T_ph_out_K] = water_circuit(x, Q_HVH_W, Q_PH_W, n_main_act, capacity, u_bp, n_hc, u_fb, u_cv2, u_cv3, fan, T_cabin_K, hvacP)'
'% Lumped thermo-hydraulic hot-water circuit.'
'% x = [T_ret T_hvh T_sup T_fbD T_fbP T_cvFL T_cvML T_cvRL T_cvFR T_cvMR T_cvRR T_ph] (K)'
'lk = hvacP.leak; cp = hvacP.cp;'
'% capacity < 1 models a failing / blocked pump: lower head AND higher internal resistance'
'cap = min(max(capacity, 0.001), 1);'
'n_main = n_main_act*sqrt(cap);'
'G_main = 1/sqrt(1/hvacP.G_main^2 - 1/hvacP.G_pump_int^2 + 1/(hvacP.G_pump_int*cap)^2);'
'% valve openings with leakage (never fully closed -> no singularity)'
'o_fb  = lk + (1 - lk)*min(max(u_fb, 0), 1);'
'o_fbb = lk + (1 - lk)*min(max(1 - u_fb, 0), 1);'
'o_c3  = lk + (1 - lk)*min(max(u_cv3, 0), 1);'
'o_c3b = lk + (1 - lk)*min(max(1 - u_cv3, 0), 1);'
'o_c2  = lk + (1 - lk)*min(max(u_cv2, 0), 1);'
'o_bp  = lk + (1 - lk)*min(max(u_bp, 0), 1);'
'% ---- branch conductances G = mdot/sqrt(dp)'
'G_fb_c = hvacP.G_three_way*o_fb;'
'G_fb_b = hvacP.G_three_way*o_fbb;'
'if hvacP.frontbox_mode_id == 1'
'    G_units = 2*hvacP.G_fb_unit;'
'else'
'    G_units = 1/sqrt(1/hvacP.G_fb_bal^2 + 2/hvacP.G_fb_hx^2);'
'end'
'G_fb_cons = 1/sqrt(1/G_fb_c^2 + 1/hvacP.G_fb_cons_fixed^2 + 1/G_units^2);'
'G_fb_byp = 1/sqrt(1/G_fb_b^2 + 1/hvacP.G_fb_bpp^2);'
'G_FB = 1/sqrt(1/hvacP.G_fb_line^2 + 1/(G_fb_cons + G_fb_byp)^2);'
'G_cv_c = 1/sqrt(1/(hvacP.G_three_way*o_c3)^2 + 1/hvacP.G_cv_bank^2);'
'G_cv_b = 1/sqrt(1/(hvacP.G_three_way*o_c3b)^2 + 1/hvacP.G_cv_bpp^2);'
'G_CV = 1/sqrt(1/hvacP.G_cv_line^2 + 1/(hvacP.G_two_way*o_c2)^2 + 1/hvacP.G_hc_int^2 + 1/(G_cv_c + G_cv_b)^2);'
'G_BP = 1/sqrt(1/(hvacP.G_bp_valve*o_bp)^2 + 1/hvacP.G_bp_fixed^2);'
'G_PH = hvacP.G_ph;'
'H_m = hvacP.dp0_main*n_main*abs(n_main);'
'H_hc = hvacP.dp0_hc*n_hc*abs(n_hc);'
'H_m_eff = H_m - hvacP.check_crack;'
'% ---- supply-return pressure difference dP from the mass balance (bisection)'
'lo = -H_hc - 1;'
'hi = max(H_m_eff, 0) + 1;'
'dP = 0;'
'for it = 1:60'
'    dP = 0.5*(lo + hi);'
'    Mloop = G_main*sqrt(max(H_m_eff - dP, 0));'
'    Mbr = (G_FB + G_PH + G_BP)*sqrt(max(dP, 0)) + G_CV*sqrt(max(dP + H_hc, 0));'
'    if Mloop - Mbr > 0'
'        lo = dP;'
'    else'
'        hi = dP;'
'    end'
'end'
'm_fb = G_FB*sqrt(max(dP, 0));'
'm_ph = G_PH*sqrt(max(dP, 0));'
'm_bp = G_BP*sqrt(max(dP, 0));'
'm_cv = G_CV*sqrt(max(dP + H_hc, 0));'
'M = m_fb + m_ph + m_bp + m_cv;'
'm_fbc = m_fb*G_fb_cons/(G_fb_cons + G_fb_byp);'
'm_fbb = m_fb - m_fbc;'
'm_cvc = m_cv*G_cv_c/(G_cv_c + G_cv_b);'
'm_cvb = m_cv - m_cvc;'
'Tr = x(1); Th = x(2); Ts = x(3);'
'% ---- frontboxes: water flow per unit and inlet temperatures'
'if hvacP.frontbox_mode_id == 1'
'    mD = m_fbc/2; mP = m_fbc/2; TinD = Ts; TinP = Ts;'
'else'
'    mD = m_fbc; mP = m_fbc; TinD = Ts; TinP = x(4);'
'end'
'% ---- frontbox air side (e-NTU): heat leaving the water'
'f = min(max(fan, 0), 1);'
'Ca = (hvacP.frontbox_air_natural_fraction + (1 - hvacP.frontbox_air_natural_fraction)*f)*hvacP.frontbox_air_C_nominal_W_K;'
'UAf = hvacP.frontbox_UA_W_K*(0.2 + 0.8*f);'
'mU = [mD; mP];'
'TinU = [TinD; TinP];'
'Q_FB_air_W = zeros(2, 1);'
'for k = 1:2'
'    Cmin = min(mU(k)*cp, Ca);'
'    if Cmin > 1e-6'
'        eff = min(hvacP.frontbox_effectiveness, 1 - exp(-UAf/Cmin));'
'        Q_FB_air_W(k) = eff*Cmin*(TinU(k) - T_cabin_K);'
'    end'
'end'
'% ---- convectors: 2 parallel chains (left / right), 3 units in series each'
'mc = m_cvc/2;'
'Tcv_in = [Ts; x(6); x(7); Ts; x(9); x(10)];'
'Q_CV_air_W = zeros(6, 1);'
'Cwc = mc*cp;'
'if Cwc > 1e-6'
'    effc = 1 - exp(-hvacP.convector_UA_each_W_K/Cwc);'
'    for k = 1:6'
'        Q_CV_air_W(k) = effc*Cwc*(Tcv_in(k) - T_cabin_K);'
'    end'
'end'
'% ---- mixing at the branch returns and at the main return junction'
'if hvacP.frontbox_mode_id == 1'
'    Tfb_out = (mD*x(4) + mP*x(5) + m_fbb*Ts)/max(m_fb, 1e-9);'
'else'
'    Tfb_out = (m_fbc*x(5) + m_fbb*Ts)/max(m_fb, 1e-9);'
'end'
'if m_fb < 1e-6, Tfb_out = Ts; end'
'Tcv_ret = 0.5*(x(8) + x(11));'
'Tcv_mix = (m_cvc*Tcv_ret + m_cvb*Ts)/max(m_cv, 1e-9);'
'if m_cv < 1e-6, Tcv_mix = Ts; end'
'Hin = m_fb*Tfb_out + m_cv*Tcv_mix + m_ph*x(12) + m_bp*Ts;'
'if M > 1e-6'
'    Tjr = Hin/M;'
'else'
'    Tjr = Tr;'
'end'
'% ---- energy balances of the 12 water nodes'
'dx = zeros(12, 1);'
'dx(1) = cp*(Hin - M*Tr)/hvacP.C_ret;'
'dx(2) = (cp*M*(Tr - Th) + Q_HVH_W)/hvacP.C_hvh;'
'dx(3) = cp*M*(Th - Ts)/hvacP.C_sup;'
'dx(4) = (cp*mD*(TinD - x(4)) - Q_FB_air_W(1))/hvacP.C_fb;'
'dx(5) = (cp*mP*(TinP - x(5)) - Q_FB_air_W(2))/hvacP.C_fb;'
'for k = 1:6'
'    dx(5+k) = (cp*mc*(Tcv_in(k) - x(5+k)) - Q_CV_air_W(k))/hvacP.C_cv;'
'end'
'dx(12) = (cp*m_ph*(Ts - x(12)) + Q_PH_W)/hvacP.C_ph;'
'% ---- measurements'
'pR = hvacP.p_tank;'
'pS = pR + dP;'
'p_in = pR - 0.25*(M/hvacP.G_main)^2;'
'p_out = p_in + H_m - (M/(hvacP.G_pump_int*cap))^2;'
'if hvacP.frontbox_mode_id == 2'
'    Tfb_mid = x(4);'
'else'
'    Tfb_mid = Ts;'
'end'
'T_water_K = [Tr; Tr; Tr; Th; Ts; Tjr; Ts; Tfb_out; Ts; Tcv_ret; Ts; x(12); x(6); x(7); x(9); x(10); Tfb_mid];'
'p_water_Pa = [p_in; p_out; p_out - 0.1*dP; pS + 0.05*dP; pS; pR; pS - 0.3*dP; pR + 0.3*dP; pS - 0.3*dP; pR + 0.3*dP; pS - 0.6*dP; pR + 0.2*dP; pS - 0.5*dP; pS - 0.6*dP; pS - 0.5*dP; pS - 0.6*dP; pS - 0.3*dP];'
'mdot_kg_s = [M; m_fbc; m_cvc; m_bp; m_ph];'
'T_HVH_in_K = Tr;'
'T_HVH_out_K = Th;'
'mdot_main = M;'
'mdot_ph = m_ph;'
'T_ph_out_K = x(12);'
'end'
}, newline);
end

%% =========================================================================
%%                     RUN, PLOTS, KPIs, VERIFICATION
%% =========================================================================
function R = ecoach_run(M)
P = applyParams(M);
fprintf('Simulating scenario %d (%g s) ...\n', P.test_scenario, P.Tstop);
tic;
out = sim(M, 'StopTime', num2str(P.Tstop), 'ReturnWorkspaceOutputs', 'on');
fprintf('Simulation finished in %.1f s wall time.\n', toc);
R = readLogs(out);
end

function R = readLogs(out)
s = out.get('log_T_cabin_front_C');
R.t = s.time(:);
R.sp     = logv(out, 'setpoint_C');
R.Tf     = logv(out, 'T_cabin_front_C');
R.Tr     = logv(out, 'T_cabin_rear_C');
R.Tcab   = 0.5*(R.Tf + R.Tr);
R.Tw     = logv(out, 'T_water_C');      % 17 columns
R.mdot   = logv(out, 'mdot_kg_s');      % main frontbox convector bypass preheater
R.cmd    = logv(out, 'safe_cmd');       % 11 commands after Safety_Manager
R.Q_HVH  = logv(out, 'Q_HVH_W');
R.P_HVH  = logv(out, 'P_el_HVH_W');
R.Q_PH   = logv(out, 'Q_PH_W');
R.P_PH   = logv(out, 'P_el_PH_W');
R.Q_FB   = logv(out, 'Q_FB_total_W');
R.Q_CV   = logv(out, 'Q_CV_total_W');
R.P_fan  = logv(out, 'fan_power_W');
R.pos    = logv(out, 'actuator_pos');   % main_pump bypass hc_pump fb_valve cv_2way cv_3way
R.faults = logv(out, 'faults');         % 10 columns
R.p      = logv(out, 'p_water_Pa');
R.Tair   = logv(out, 'T_cabin_air_K');
end

function v = logv(out, name)
% Returns a logged signal as [time x channels].
s = out.get(['log_' name]);
if isempty(s)
    error('eCoach:log', 'Logged variable log_%s not found.', name);
end
v = double(s.signals.values);
nt = numel(s.time);
if ndims(v) == 3
    v = reshape(permute(v, [3 1 2]), nt, []);
elseif size(v, 1) ~= nt
    v = v.';
end
end

function ecoach_plots(R, P)
tm = R.t/60;
figure('Name', '1 Cabin temperatures', 'Color', 'w');
plot(tm, R.sp, 'k--', tm, R.Tf, tm, R.Tr, tm, R.Tcab, 'LineWidth', 1.2); grid on
xlabel('t [min]'); ylabel('T [\circC]');
legend('Setpoint', 'Front sensor', 'Rear sensor', 'Feedback (average)', 'Location', 'southeast');
title(sprintf('Scenario %d - cabin temperatures', P.test_scenario));

figure('Name', '2 Water temperatures', 'Color', 'w');
plot(tm, R.Tw(:, 3:10), 'LineWidth', 1.1); grid on
xlabel('t [min]'); ylabel('T [\circC]');
legend('HVH in', 'HVH out', 'Main supply', 'Main return', 'Frontbox in', 'Frontbox out', ...
    'Convector supply', 'Convector return', 'Location', 'best');
title('Supply / return water temperatures');

figure('Name', '3 Mass flow rates', 'Color', 'w');
plot(tm, R.mdot, 'LineWidth', 1.1); grid on; hold on
plot(tm([1 end]), P.bypass_min_mdot_kg_s*[1 1], 'k:');
xlabel('t [min]'); ylabel('mass flow [kg/s]');
legend('Main', 'Frontbox consumers', 'Convector bank', 'Main bypass', 'Pre-heater', 'Bypass minimum', 'Location', 'best');
title('Branch mass flow rates');

figure('Name', '4 Heater power and pump commands', 'Color', 'w');
subplot(2, 1, 1);
plot(tm, R.P_HVH/1e3, tm, R.Q_HVH/1e3, tm, R.P_PH/1e3, tm, (R.Q_FB + R.Q_CV)/1e3, 'LineWidth', 1.1); grid on
ylabel('[kW]'); legend('HVH electric', 'HVH heat to water', 'Pre-heater electric', 'Heat to cabin', 'Location', 'best');
subplot(2, 1, 2);
plot(tm, R.cmd(:, 2), tm, R.cmd(:, 3), tm, R.cmd(:, 4), tm, R.pos(:, 1), 'LineWidth', 1.1); grid on
xlabel('t [min]'); ylabel('[-]');
legend('Heater power cmd', 'Main pump cmd', 'Heating pump cmd', 'Main pump actual', 'Location', 'best');

figure('Name', '5 Valve positions and bypass', 'Color', 'w');
subplot(2, 1, 1);
plot(tm, R.pos(:, 4), tm, R.pos(:, 5), tm, R.pos(:, 6), tm, R.pos(:, 2), 'LineWidth', 1.1); grid on
ylabel('opening [-]'); legend('Frontbox 3-way', 'Convector 2-way', 'Convector 3-way', 'Main bypass', 'Location', 'best');
subplot(2, 1, 2);
plot(tm, R.mdot(:, 4), 'k', tm([1 end]), P.bypass_min_mdot_kg_s*[1 1], 'r--', 'LineWidth', 1.2); grid on
xlabel('t [min]'); ylabel('[kg/s]'); legend('Bypass flow', 'Minimum', 'Location', 'best');

figure('Name', '6 Fault states', 'Color', 'w');
names = {'overtemp', 'low flow', 'sensor', 'pressure', 'pump', 'freeze', 'valve', 'cabin OT', 'critical', 'any'};
hold on
for k = 1:10
    stairs(tm, R.faults(:, k) + 1.5*(k-1), 'LineWidth', 1.2);
end
grid on; set(gca, 'YTick', 1.5*(0:9), 'YTickLabel', names); xlabel('t [min]'); title('Fault flags (offset)');
end

function ecoach_kpis(R, P)
t = R.t;
k18 = find(R.Tcab >= 18, 1);
active = R.cmd(:, 3) > 0.2 & t > P.t_hvac_on + 30;
fprintf('\n================ KPIs - scenario %d ================\n', P.test_scenario);
if isempty(k18)
    fprintf('Cabin reaching time to 18 degC          : not reached\n');
else
    fprintf('Cabin reaching time to 18 degC          : %.1f min after HVAC on\n', (t(k18) - P.t_hvac_on)/60);
end
thr = P.setpoint_C - P.reach_tol_K;
kS = find(R.Tcab >= thr & t > P.t_hvac_on, 1);
if isempty(kS)
    fprintf('TIME TO SETPOINT (cabin >= %.1f degC)   : not reached within %.1f h (cabin at end %.2f degC)\n', ...
        thr, (t(end) - P.t_hvac_on)/3600, R.Tcab(end));
else
    fprintf('TIME TO SETPOINT (cabin >= %.1f degC)   : %.1f min after HVAC on\n', thr, (t(kS) - P.t_hvac_on)/60);
end
fprintf('Maximum heater outlet temperature       : %.1f degC\n', max(R.Tw(:, 4)));
fprintf('Average heater electrical power         : %.2f kW\n', mean(R.P_HVH)/1e3);
fprintf('Total heater energy consumption         : %.3f kWh\n', trapz(t, R.P_HVH)/3.6e6);
fprintf('Total heater + pre-heater + fan energy  : %.3f kWh\n', trapz(t, R.P_HVH + R.P_PH + R.P_fan)/3.6e6);
if any(active)
    fprintf('Minimum main flow rate (pump running)   : %.3f kg/s\n', min(R.mdot(active, 1)));
end
fprintf('Maximum cabin temperature               : %.2f degC\n', max(R.Tcab));
fprintf('Simulation completed without critical fault: %s\n', mat2str(~any(R.faults(:, 9) > 0.5)));
if P.test_scenario == 3
    win = t >= 620 & t <= 780;
    mb = min(R.mdot(win, 4));
    fprintf('Scenario 3: min bypass flow while consumers closed = %.3f kg/s -> %s\n', mb, ...
        passfail(mb >= P.bypass_min_mdot_kg_s));
elseif P.test_scenario == 4
    kf = find(R.faults(:, 2) > 0.5, 1);
    if isempty(kf)
        fprintf('Scenario 4: low-flow fault NOT detected -> FAIL\n');
    else
        after = t > t(kf) + 10;
        fprintf('Scenario 4: low-flow fault at %.0f s, heater power after %.0f W, bypass %.2f -> %s\n', ...
            t(kf), max(R.P_HVH(after)), R.pos(end, 2), ...
            passfail(max(R.P_HVH(after)) < 100 && R.pos(end, 2) > 0.9));
    end
end
end

function ecoach_verify(M, rootDir)
fprintf('\n================ Verification ================\n');
scnUser = get_param([M '/Parameters'], 'test_scenario');   % restored at the end
rep = @(id, ok, msg) fprintf('%-4s %-55s %s\n', id, msg, passfail(ok));
rep('1', exist(fullfile(rootDir, [M '.slx']), 'file') == 2, 'Model file exists');
req = {'Plant_Hydraulic_Circuit', 'High_Voltage_Heater', 'Frontbox_Branch', 'Convector_Branch', ...
       'PreHeater_Branch', 'Cabin_Thermal_Model', 'HVAC_Control', 'Safety_Manager', ...
       'Sensors_and_Signal_Conditioning', 'Test_Scenarios', 'Results', 'Parameters'};
miss = req(cellfun(@(nm) getSimulinkBlockHandle([M '/' nm]) == -1, req));
rep('2', isempty(miss), 'All required subsystems present (incl. Parameters, Results)');
rep('3', isempty(findOpenPorts(M)), 'No unconnected ports');
fprintf('%-4s %-55s %s\n', '4-5', 'Solver Configuration / TL Reference', 'N/A (no Simscape)');
ok6 = true;
try
    setScenario(M, 1);
    applyParams(M);
    set_param(M, 'SimulationCommand', 'update');
catch ME
    ok6 = false; fprintf(2, '%s\n', ME.getReport('extended'));
end
rep('6', ok6, 'Update diagram');
ok7 = false;
if ok6
    try
        sim(M, 'StopTime', '10', 'ReturnWorkspaceOutputs', 'on');
        ok7 = true;
    catch ME
        fprintf(2, '%s\n', ME.getReport('extended'));
    end
end
rep('7', ok7, '10 s simulation completes');
ok8 = false; ok9 = false; ok10 = false; ok11 = false;
if ok7
    try
        setScenario(M, 1);
        P = applyParams(M);
        R = readLogs(sim(M, 'StopTime', '600', 'ReturnWorkspaceOutputs', 'on'));
        Tout = R.Tw(:, 4);
        ok8 = all(isfinite(Tout)) && max(Tout) < P.T_heater_max_K - 273.15 && min(Tout) > -40;
        ok9 = all(isfinite(R.mdot(:))) && min(R.mdot(:)) > -1e-6 && max(R.mdot(:)) < 3;
        ok10 = all(isfinite(R.Tair));
        ok11 = ~any(R.faults(:, 9) > 0.5);
        fprintf('     600 s cold start: max HVH out %.1f degC, main flow %.3f..%.3f kg/s, cabin %.1f -> %.1f degC\n', ...
            max(Tout), min(R.mdot(:, 1)), max(R.mdot(:, 1)), R.Tair(1) - 273.15, R.Tair(end) - 273.15);
    catch ME
        fprintf(2, '%s\n', ME.getReport('extended'));
    end
end
rep('8', ok8, 'Heater outlet temperature within physical limits');
rep('9', ok9, 'Mass flow rates not negative / not excessive');
rep('10', ok10, 'Cabin temperature state finite');
rep('11', ok11, 'Fault-free scenario: no critical fault');
ok12 = false;
if ok7
    try
        setScenario(M, 4);
        applyParams(M);
        R = readLogs(sim(M, 'StopTime', '900', 'ReturnWorkspaceOutputs', 'on'));
        kf = find(R.faults(:, 2) > 0.5, 1);
        if ~isempty(kf)
            after = R.t > R.t(kf) + 10;
            ok12 = max(R.P_HVH(after)) < 100 && R.pos(end, 2) > 0.9;
            fprintf('     low-flow fault at %.0f s, heater power after %.0f W, bypass %.2f\n', ...
                R.t(kf), max(R.P_HVH(after)), R.pos(end, 2));
        else
            fprintf('     low-flow fault was not raised\n');
        end
    catch ME
        fprintf(2, '%s\n', ME.getReport('extended'));
    end
end
rep('12', ok12, 'Low-flow scenario: fault, heater shutdown, bypass open');
set_param([M '/Parameters'], 'test_scenario', scnUser);
applyParams(M);
fprintf('==============================================\n');
end

function s = passfail(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end