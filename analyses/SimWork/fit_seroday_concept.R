####################################################################################
## Purpose: Plot for Figure 1 Showing Delays and Inference Framework
##
## Notes:
####################################################################################
setwd("/proj/ideel/meshnick/users/NickB/Projects/reestimate_covidIFR_analysis/")
set.seed(48)
library(COVIDCurve)
library(tidyverse)
library(drake)
source("R/covidcurve_helper_functions.R")
source("R/my_themes.R")

#............................................................
# Read in Various Scenarios for Incidence Curves
#...........................................................
infxn_shapes <- readr::read_csv("data/simdat/infxn_curve_shapes.csv")
interveneflat <- infxn_shapes$intervene
# note need more infxns for sensitivity to be apparent on conceptual diagrams
interveneflat <- interveneflat * 3
interveneflat <- c(interveneflat, round(seq(from = interveneflat[200],
                                      to = 10, length.out = 100)))



#............................................................
# setup fatality data
#............................................................
# make up fatality data
fatalitydata <- tibble::tibble(Strata = "ma1",
                               IFR = 0.1,
                               Rho = 1)
demog <- tibble::tibble(Strata = "ma1",
                        popN = 3e6)

# run COVIDCurve sims for no seroreversion and seroreversion
dat <- COVIDCurve::Agesim_infxn_2_death(
  fatalitydata = fatalitydata,
  demog = demog,
  m_od = 19.26,
  s_od = 0.76,
  curr_day = 300,
  infections = interveneflat,
  simulate_seroreversion = FALSE,
  sens = 0.85,
  spec = 0.95,
  sero_delay_rate = 18.3,
  return_linelist = FALSE)



#............................................................
#----- Model & Fit #-----
#...........................................................
#......................
# wrangle input data from non-seroreversion fit
#......................
# liftover obs serology
sero_day <- 150
OneDayobs_serology <- dat$StrataAgg_Seroprev %>%
  dplyr::group_by(Strata) %>%
  dplyr::filter(ObsDay %in% sero_day) %>%
  dplyr::mutate(
    SeroPos = round(ObsPrev * testedN),
    SeroN = testedN,
    SeroLCI = NA,
    SeroUCI = NA) %>%
  dplyr::rename(
    SeroPrev = ObsPrev) %>%
  dplyr::mutate(SeroStartSurvey = sero_day - 5,
                SeroEndSurvey = sero_day + 5) %>%
  dplyr::select(c("SeroStartSurvey", "SeroEndSurvey", "Strata", "SeroPos", "SeroN", "SeroPrev", "SeroLCI", "SeroUCI")) %>%
  dplyr::ungroup(.) %>%
  dplyr::arrange(SeroStartSurvey, Strata)


# proportion deaths
prop_deaths <- dat$StrataAgg_TimeSeries_Death %>%
  dplyr::group_by(Strata) %>%
  dplyr::summarise(deaths = sum(Deaths)) %>%
  dplyr::ungroup(.) %>%
  dplyr::mutate(PropDeaths = deaths/sum(dat$Agg_TimeSeries_Death$Deaths)) %>%
  dplyr::select(-c("deaths"))

# make data out
oneday_inputdata <- list(obs_deaths = dat$Agg_TimeSeries_Death,
                     prop_deaths = prop_deaths,
                     obs_serology = OneDayobs_serology)

#......................
# wrangle input data from non-seroreversion fit
#......................
# sero tidy up
sero_days <- c(140, 160)
TwoDays_obs_serology <- dat$StrataAgg_Seroprev %>%
  dplyr::group_by(Strata) %>%
  dplyr::filter(ObsDay %in% sero_days) %>%
  dplyr::mutate(
    SeroPos = round(ObsPrev * testedN),
    SeroN = testedN,
    SeroLCI = NA,
    SeroUCI = NA) %>%
  dplyr::rename(
    SeroDay = ObsDay,
    SeroPrev = ObsPrev) %>%
  dplyr::mutate(SeroStartSurvey = sero_days - 5,
                SeroEndSurvey = sero_days + 5) %>%
  dplyr::select(c("SeroStartSurvey", "SeroEndSurvey", "Strata", "SeroPos", "SeroN", "SeroPrev", "SeroLCI", "SeroUCI")) %>%
  dplyr::ungroup(.) %>%
  dplyr::arrange(SeroStartSurvey, Strata)

# proportion deaths
prop_deaths <- dat$StrataAgg_TimeSeries_Death %>%
  dplyr::group_by(Strata) %>%
  dplyr::summarise(deaths = sum(Deaths)) %>%
  dplyr::ungroup(.) %>%
  dplyr::mutate(PropDeaths = deaths/sum(dat$Agg_TimeSeries_Death$Deaths)) %>%
  dplyr::select(-c("deaths"))

# make data out
twodays_inputdata <- list(obs_deaths = dat$Agg_TimeSeries_Death,
                          prop_deaths = prop_deaths,
                          obs_serology = TwoDays_obs_serology)



#......................
# make IFR model
#......................
# paramdf
# sens/spec
sens_spec_tbl <- tibble::tibble(name =  c("sens",  "spec"),
                                min =   c(0.5,      0.5),
                                init =  c(0.85,     0.99),
                                max =   c(1,        1),
                                dsc1 =  c(850.5,    990.5),
                                dsc2 =  c(150.5,    10.5))

# delay priors
tod_paramsdf <- tibble::tibble(name = c("mod", "sod", "sero_con_rate"),
                               min  = c(18,     0,     16),
                               init = c(19,     0.79,  18),
                               max =  c(20,     1,     21),
                               dsc1 = c(19.26,  2370,  18.3),
                               dsc2 = c(0.1,    630,   0.1))



# make param dfs
ifr_paramsdf <- make_ma_reparamdf(num_mas = 1, upperMa = 0.4)
knot_paramsdf <- make_splinex_reparamdf(max_xvec = list("name" = "x4", min = 180, init = 190, max = 200, dsc1 = 180, dsc2 = 200),
                                        num_xs = 4)
infxn_paramsdf <- make_spliney_reparamdf(max_yvec = list("name" = "y3", min = 0, init = 9, max = 15.42, dsc1 = 0, dsc2 = 15.42),
                                         num_ys = 5)
# bring together
df_params <- rbind.data.frame(ifr_paramsdf, infxn_paramsdf, knot_paramsdf, sens_spec_tbl, tod_paramsdf)


# make mod
mod1 <- COVIDCurve::make_IFRmodel_age$new()
mod1$set_MeanTODparam("mod")
mod1$set_CoefVarOnsetTODparam("sod")
mod1$set_IFRparams("ma1")
mod1$set_Knotparams(paste0("x", 1:4))
mod1$set_relKnot("x4")
mod1$set_Infxnparams(paste0("y", 1:5))
mod1$set_relInfxn("y3")
mod1$set_Serotestparams(c("sens", "spec", "sero_con_rate"))

#......................
# make model for serorev and regular
#......................
mod1_oneday <- mod1
mod1_twodays <- mod1
# one day
mod1_oneday$set_data(oneday_inputdata)
mod1_oneday$set_demog(demog)
mod1_oneday$set_paramdf(df_params)
mod1_oneday$set_rcensor_day(.Machine$integer.max)
# two days
mod1_twodays$set_data(twodays_inputdata)
mod1_twodays$set_demog(demog)
mod1_twodays$set_paramdf(df_params)
mod1_twodays$set_rcensor_day(.Machine$integer.max)

#............................................................
#---- Come Together #----
#...........................................................
bvec <- seq(5, 2.5, length.out = 50)

fit_map <- tibble::tibble(
  name = c("OneDay_mod", "TwoDays_mod"),
  infxns = list(interveneflat, NULL), # Null sinse same infections
  simdat = list(dat, NULL),
  modelobj = list(mod1_oneday, mod1_twodays),
  rungs = 50,
  GTI_pow = list(bvec),
  burnin = 1e4,
  samples = 1e4,
  thinning = 10)


#......................
# fitmap out
#......................
# select what we need for fits and make outpaths
dir.create("data/param_map/SeroDays_Concept/", recursive = T)
lapply(split(fit_map, 1:nrow(fit_map)), function(x){
  saveRDS(x, paste0("data/param_map/SeroDays_Concept/",
                    x$name, "_rung", x$rungs, "_burn", x$burnin, "_smpl", x$samples, ".RDS"))
})



#............................................................
# MCMC Object
#...........................................................
run_MCMC <- function(path) {
  mod <- readRDS(path)
  #......................
  # make cluster object to parallelize chains
  #......................
  n_chains <- 10
  n_cores <- parallel::detectCores()

  if (n_cores < n_chains) {
    mkcores <- n_cores - 1
  } else {
    mkcores <- n_chains
  }

  cl <- parallel::makeCluster(mkcores)

  fit <- COVIDCurve::run_IFRmodel_age(IFRmodel = mod$modelobj[[1]],
                                      reparamIFR = FALSE,
                                      reparamInfxn = TRUE,
                                      reparamKnots = TRUE,
                                      chains = n_chains,
                                      burnin = mod$burnin,
                                      samples = mod$samples,
                                      rungs = mod$rungs,
                                      GTI_pow = mod$GTI_pow[[1]],
                                      cluster = cl,
                                      thinning = 10)
  parallel::stopCluster(cl)
  gc()

  # out
  dir.create("/proj/ideel/meshnick/users/NickB/Projects/reestimate_covidIFR_analysis/results/SeroDays_Concept/", recursive = TRUE)
  outpath = paste0("/proj/ideel/meshnick/users/NickB/Projects/reestimate_covidIFR_analysis/results/SeroDays_Concept/",
                   mod$name, "_rung", mod$rungs, "_burn", mod$burnin, "_smpl", mod$samples, ".RDS")
  saveRDS(fit, file = outpath)
  return(0)
}


#............................................................
# Make Drake Plan
#...........................................................
# due to R6 classes being stored in environment https://github.com/ropensci/drake/issues/961
# Drake can't find <environment> in memory (obviously).
# Need to either wrap out of figure out how to nest better

# read files in after sleeping to account for file lag
Sys.sleep(60)
file_param_map <- list.files(path = "data/param_map/SeroDays_Concept/",
                             pattern = "*.RDS",
                             full.names = TRUE)
file_param_map <- tibble::tibble(path = file_param_map)


#............................................................
# Make Drake Plan
#...........................................................
plan <- drake::drake_plan(
  fits = target(
    run_MCMC(path),
    transform = map(
      .data = !!file_param_map
    )
  )
)


#......................
# call drake to send out to slurm
#......................
options(clustermq.scheduler = "slurm",
        clustermq.template = "drake_clst/slurm_clustermq_LL.tmpl")
make(plan, parallelism = "clustermq", jobs = nrow(file_param_map),
     log_make = "SeroDays_drake.log", verbose = 2,
     log_progress = TRUE,
     log_build_times = FALSE,
     recoverable = FALSE,
     history = FALSE,
     session_info = FALSE,
     lock_envir = FALSE, # unlock environment so parallel::clusterApplyLB in drjacoby can work
     lock_cache = FALSE)



cat("************** Drake Finished **************************")



