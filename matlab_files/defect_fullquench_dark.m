%cleaner version of quenching script

%main function, takes in frozen defects, defects structure, conditions
%structure, and material properties

function[fullquench_dark_sol] = defect_fullquench_dark(equilib_sol, conditions, defects)

% %%%% Constants  %%%%
% q = 1.602176565e-19;
% h = 6.62606957e-34;
% kB = 8.6173324e-5;
% mo = 9.1093837e-31;

%%%%%  initialize the solution structure - these values are just copied
%%%%%  from the equilibrium solution
fullquench_dark_sol.T_equilibrium = equilib_sol.T_equilibrium;
fullquench_dark_sol.Nd = equilib_sol.Nd;
fullquench_dark_sol.Na = equilib_sol.Na;
fullquench_dark_sol.defect_names = equilib_sol.defect_names;
fullquench_dark_sol.chargestate_names = equilib_sol.chargestate_names;
fullquench_dark_sol.defects = equilib_sol.defects;  % for fullquenching the total number of defects is constant but charge states and n, p can change

%% these values are zero holders for the solution generated by the fullquench calc
fullquench_dark_sol.n = zeros(size(equilib_sol.n));
fullquench_dark_sol.p = zeros(size(equilib_sol.p));
fullquench_dark_sol.EFn = zeros(size(equilib_sol.EFn));
fullquench_dark_sol.EFp = zeros(size(equilib_sol.EFp));
fullquench_dark_sol.chargestates = zeros(size(equilib_sol.chargestates));
fullquench_dark_sol.charge_bal_err = zeros(size(equilib_sol.charge_bal_err));

%%% for now, assume 1 fullquenching temperature
kBT_fullquench = conditions.T_fullquench*conditions.kB;

for j = 1:size(equilib_sol.T_equilibrium, 1)  % loops over the equilibrium temperatures, keeping T_quench the same
    [guess] = FQ_EF_guess(conditions.EgT_fullquench);   % get a guess for EF close to minimum using trial and error
    EF_out = fzero(@fullquench_charge_bal,guess);
    fullquench_dark_sol.EFn(j) = EF_out;
    fullquench_dark_sol.EFp(j) = EF_out;
    [fullquench_dark_sol.n(j), fullquench_dark_sol.p(j)] = fullquench_carrier_concentrations(EF_out);
    [fullquench_dark_sol.chargestates(j,:)] = fullquench_chargestate_concentrations(EF_out);  % compute the defect and carrier concentrations from the EF
    [fullquench_dark_sol.charge_bal_err(j)] = fullquench_charge_bal(EF_out);
end
%%%%%%%%%%%%%% end of main calc  %%%%%%%%%%%%%%%%%%




%%%%%%%%%%%%%%% nested subroutines %%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%% function that uses grid search to get EF close to the charge
%%%% balance solution.  It will output two values for EF that bracket the solution unless something is strange about the charge_bal vs EF (i.e. its not monotonic   %%%%%%%%%%%%
% could change this to just guess based on net doping rather than grid
% seach
    function [guess] = FQ_EF_guess(FQ_Egap)   % keep kBT and Eg as local variables in this function

        EF_int = kBT_fullquench/2;   % this guarantees you can't miss the solution whcih should be thus within kB/2 of the guess
        EF_grid = (-5*kBT_fullquench):EF_int:(ceil(FQ_Egap/EF_int)*EF_int + 5*kBT_fullquench);  % this makes a grid to check over the range -5kBT to Eg+5kBT.  This is ok since we have Fermi-Dirac stats
        nn = size(EF_grid,2);
        errs = zeros(1,nn);

        for i=1:nn
            guess = EF_grid(i);
            errs(i)=fullquench_charge_bal(guess);
        end

        edge_index = find(diff(sign(errs))~=0);   %  this finds the rising/falling edge where error changes sign

        if sum(size(edge_index)==[1 1])==2
            min_index = [edge_index edge_index+1];   % so we are finding the two guesses that bracket the solution one + and one -
            %     elseif sum(size(edge_index)~=[1 1])==2
            %         disp('waring: charge balance error may not be monotonic')
        elseif sum(size(edge_index)==[1 2])==2
            min_index = edge_index;
        else
            error('something strange about charge balance error vs EF - solutions may not be valid')
        end

        guess = EF_grid(min_index);
        %
        % %%%% plot the charge balance error function vs EF position if you like
        % figure(1)
        % clf
        % plot(EF_grid,errs)
        % hold on
        % plot(EF_grid(min_index),errs(min_index),'ro')  %plot the EF_guess

    end    %%%% end EF_guess





%%%% function that computes the net charge
    function charge_bal = fullquench_charge_bal(EF)
        [n,p] = fullquench_carrier_concentrations(EF);
        [N_chargestates_fullquench] = fullquench_chargestate_concentrations(EF);
        charge_bal = (sum( defects.cs_charge.* N_chargestates_fullquench') + p - n + conditions.Nd - conditions.Na);
    end
%%%% end charge_bal   %%%%%%%%%%%%%





%% Given EF and total number of each defect type, figure out the number of each charge state.

    function [N_chargestates_fullquench] = fullquench_chargestate_concentrations(EF)

        % set up arrays
        N_chargestates_fullquench = zeros(1,defects.num_chargestates);
        Z = zeros(1,defects.num_defects);

        % calculate Boltzmann factors for all charge states
        dH_rel = defects.cs_dHo + defects.cs_charge*EF;  % the formation enthalpy of the defects without the chem potential term (quench assumes no mass exchange)
        Boltz_facs = exp(-dH_rel/kBT_fullquench);

        for i = 1:defects.num_defects  % loop over defects (defect.cs_ID) - not over charge states
            indices = defects.cs_ID == i;  % find the indices of the charge states of the ith defect
            Z(i) = sum(Boltz_facs(indices)); % matrix with Z value for each defect (computed from Boltz factors for each charge state in that defect
            N_chargestates_fullquench(indices) = Boltz_facs(indices)/Z(i) * equilib_sol.defects(j,i);     % equilib_dark_sol.defects(j,i) is a scalar, Z(i) is a scalar
        end

    end  %%%% end concentrations




    function [n,p] = fullquench_carrier_concentrations(EF)   % everything here is in terms of T_fullquench
        %%%% function to compute n and p from EF  %%%%%%%%%%%%
        etaCB = (EF - conditions.EcT_fullquench)/kBT_fullquench;
        etaVB = (EF - conditions.EvT_fullquench)/kBT_fullquench;   % this looks wrong (not symmetric compared to CB case) but it is right. Direction of integration and sign on EF-Ev are both swapped.
        % %     use just Boltzmann approx
        % %     n = Tloop_conditions.Nc*exp(etaCB);   % these are right (sign swap).  Boltzmann factors should end up <1 when EF is in gap
        % %     p = Tloop_conditions.Nv*exp(-etaVB);
        % use Fermi-Dirac integrals so degenerate conditions handled correctly
        [n,nBoltz] = n_Fermi_Dirac(etaCB,conditions.NcT_fullquench);
        [p,pBoltz] = n_Fermi_Dirac(-etaVB,conditions.NvT_fullquench);
    end




end   %%%%%end main function

