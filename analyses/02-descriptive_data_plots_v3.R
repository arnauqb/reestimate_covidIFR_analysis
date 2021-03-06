#................................................................................................
## Purpose: Plot descriptive statistics
##
## Notes:
#................................................................................................
#......................
# setup
#......................
library(tidyverse)
source("R/crude_plot_summ.R")
source("R/covidcurve_helper_functions.R")
source("R/my_themes.R")
source("R/extra_plotting_functions.R")
dir.create("figures/descriptive_figures/", recursive = TRUE)

write2file <- F

#............................................................
#---- Read in and Wrangle Data #----
#...........................................................
# colors
study_cols <- readr::read_csv("data/plot_aesthetics/color_studyid_map.csv")
mycolors <- study_cols$cols
names(mycolors) <- study_cols$study_id

# care homes
deaths_ch <- readr::read_csv("data/raw/care_home_deaths.csv")

# data map
datmap <- readxl::read_excel("data/derived/derived_data_map.xlsx")
datmap <- datmap %>%
  dplyr::mutate(data = purrr::map(relpath, readRDS))

# Brazil city data for regional plot.
braz_dat_reg <- read.csv("data/derived/BRA1/BRA1_city.csv")


#......................
# wrangle & extract sero data
#......................
serohlp <- datmap %>%
  dplyr::mutate(
    seroprevdat = purrr::map(data, "seroprevMCMC"),
    sens = purrr::map(data, "sero_sens"),
    sens = purrr::map_dbl(sens, function(x){as.numeric(x$sensitivity)}),
    spec = purrr::map(data, "sero_spec"),
    spec = purrr::map_dbl(spec, function(x){as.numeric(x$specificity)})) %>%
  dplyr::select(c("seroprevdat", "sens", "spec"))

# For ITA, will assume a spec of 99.66 and spec of 88.88 based on regional stan fits
serohlp$sens[datmap$study_id == "ITA1"] <- 0.8888
serohlp$spec[datmap$study_id == "ITA1"] <- 0.9966

datmap <- datmap %>%
  dplyr::mutate(seroprev_adjdat = purrr::pmap(serohlp, adjust_seroprev))

#......................
# wrangle & extract death data
#......................
deathhlp <- datmap %>%
  dplyr::mutate(
    deathdat_long = purrr::map(data, "deaths_group"),
    popdat = purrr::map(data, "prop_pop"),
    groupingvar = breakdown,
    Nstandardization = 1e6) %>%
  dplyr::select(c("deathdat_long", "popdat", "groupingvar", "Nstandardization"))

datmap <- datmap %>%
  dplyr::mutate(std_deaths = purrr::pmap(deathhlp, standardize_deathdat))

#......................
# combine
#......................
datmap <- datmap %>%
  dplyr::mutate(plotdat = purrr::map2(.x = std_deaths, .y = seroprev_adjdat, dplyr::left_join)) # let dplyr find strata

# save out
dir.create("results/descriptive_results/", recursive = TRUE)
saveRDS(datmap, file = "results/descriptive_results/descriptive_results_datamap.RDS")


#............................................................
#---- Age Bands Plots/Descriptions #----
#...........................................................
#...........................................................
# GBR4 Jersey, GBR2 Scotland, SF_CA - no age data or too early in epidemic to have age data.
# LA_CA1, GBR2 TODO
#...........................................................
ageplotdat <- datmap %>%
  dplyr::filter(breakdown == "ageband") %>%
  dplyr::select(c("study_id","care_home_deaths", "plotdat")) %>%
  tidyr::unnest(cols = "plotdat")
ageplotdat <- dplyr::full_join(ageplotdat, study_cols, by="study_id")

#filter to only plot the latest serology when there are multiple rouunds
maxDays <- ageplotdat %>%
  dplyr::group_by(study_id) %>%
  dplyr::summarise(max_day=max(obsdaymax))
ageplotdat <- dplyr::full_join(ageplotdat, maxDays, by="study_id")
ageplotdat <- dplyr::filter(ageplotdat, obsdaymax == max_day)


#......................
# age raw seroprevalence
#......................
age_seroplot <- ageplotdat %>%
  dplyr::filter(care_home_deaths=="yes" & study_id!="CHE2") %>%
  dplyr::select(c("study_id", "age_mid", "seroprev")) %>%
  dplyr::mutate(seroprev = seroprev * 100) %>%
  ggplot() + theme_bw() +
  geom_point(aes(x = age_mid, y = seroprev, fill = study_id), shape = 21, size = 2.5, stroke = 0.2) +
  geom_line(aes(x = age_mid, y = seroprev, group=study_id,color=study_id), size = 0.3) +
  scale_fill_manual(values = mycolors, name = "study_id") +
  scale_color_manual(values = mycolors, name = "study_id") +
  xlab("Age (yrs).") + ylab("Raw Seroprevalence (%)") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/age_raw_seroplot.tiff",
                      plot = age_seroplot, width = 7, height = 5)

#......................
# age adj seroprevalence
#......................
age_seroplot <- ageplotdat %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  dplyr::select(c("study_id", "age_mid", "seroprevadj")) %>%
  dplyr::mutate(seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_line(aes(x = age_mid, y = seroprevadj, color = study_id), alpha = 0.8, size = 1.2) +
  geom_point(aes(x = age_mid, y = seroprevadj, color = study_id)) +
  scale_color_manual("Study ID", values = mycolors) +
  xlab("Age (yrs).") + ylab("Adj. Seroprevalence (%)") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/age_adj_seroplot.tiff",
                      plot = age_seroplot, width = 7, height = 5)

#......................
# crude IFR
#......................
# raw serology
age_IFRraw_plot0 <- ageplotdat %>%
  dplyr::filter(seromidpt == obsday) %>%
  dplyr::select(c("study_id","n_positive","n_tested","ageband", "age_mid", "cumdeaths", "popn", "seroprev", "seroprevadj","care_home_deaths")) %>%
  dplyr::mutate(infxns = popn * seroprev,
                crudeIFR =  cumdeaths/(infxns+cumdeaths),
                crudeIFR = ifelse(crudeIFR > 1, 1, crudeIFR),
                seroprev = seroprev * 100,
                sero_adj_infxns = popn *seroprevadj,
                sero_adjIFR = cumdeaths/(sero_adj_infxns+cumdeaths))

# write this out for later use
readr::write_csv(age_IFRraw_plot0, path = "data/derived/age_summ_IFR.csv")

### Age IFR crude.
age_IFRraw_plot2 <- age_IFRraw_plot0 %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  ggplot() + theme_bw() +
  geom_point(aes(x = age_mid, y = crudeIFR, fill = study_id), shape = 21, size = 2.5, stroke = 0.2) +
  geom_line(aes(x = age_mid, y = crudeIFR, group=study_id,color=study_id), size = 0.3) +
  scale_fill_manual(values = mycolors, name = "study_id") +
  scale_color_manual(values = mycolors, name = "study_id") +
  xlab("Age (years)") + ylab("Crude infection fatality rate") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/age_IFRraw_plot2.pdf", plot = age_IFRraw_plot2, width = 7, height = 5)

age_IFRraw_plot_log <- age_IFRraw_plot0 %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  filter(crudeIFR>0) %>%
  ggplot() + theme_bw() +
  geom_point(aes(x = age_mid, y = crudeIFR, fill = study_id), shape = 21, size = 2.5, stroke = 0.2) +
  geom_line(aes(x = age_mid, y = crudeIFR, group=study_id,color=study_id), size = 0.3) +
  scale_fill_manual(values = mycolors, name = "study_id") +
  scale_color_manual(values = mycolors, name = "study_id") +
  xlab("Age (years)") + ylab("Crude infection fatality rate") +
  xyaxis_plot_theme +
  scale_y_log10()
#  coord_cartesian(ylim=c(0.00000000001,1))
if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/age_IFRraw_plot_log.jpg",
                           plot = age_IFRraw_plot_log,width_wide = 8,height_wide = 5.5)

# seroadj
age_IFRadj_plot <- age_IFRraw_plot0 %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  ggplot() + theme_bw() +
  geom_point(aes(x = age_mid, y = sero_adjIFR, fill = study_id), shape = 21, size = 2.5, stroke = 0.2) +
  geom_line(aes(x = age_mid, y = sero_adjIFR, group=study_id,color=study_id), size = 0.3) +
  scale_fill_manual(values = mycolors, name = "study_id") +
  scale_color_manual(values = mycolors, name = "study_id") +
  xlab("Age (years)") + ylab("Adjusted infection fatality rate") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/age_IFRadj_plot.pdf", plot = age_IFRadj_plot, width = 7, height = 5)


#......................
# compare with and without care home deaths
#......................
study_ids_ch<-c(deaths_ch$study_id,paste0(deaths_ch$study_id,"_nch"))
study_cols_ch<-filter(study_cols,study_id %in% study_ids_ch)
age_IFRraw_plot_ch<-dplyr::filter(age_IFRraw_plot0,study_id %in% study_ids_ch & care_home_deaths=="yes")
age_IFRraw_plot_noch<-dplyr::filter(age_IFRraw_plot0,study_id %in% study_ids_ch & care_home_deaths=="no")

age_IFRraw_plot_ch <- ggplot() + theme_bw() +
  geom_point(aes(x = age_IFRraw_plot_noch$age_mid, y = age_IFRraw_plot_noch$crudeIFR, fill = age_IFRraw_plot_noch$study_id), shape = 21, size = 2.5, stroke = 0.2) +
  geom_line(aes(x = age_IFRraw_plot_noch$age_mid, y = age_IFRraw_plot_noch$crudeIFR, group=age_IFRraw_plot_noch$study_id,color=age_IFRraw_plot_noch$study_id), size = 0.3) +
  xlab("Age (years)") + ylab("Crude infection fatality rate") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/age_IFRraw_plot_ch.tiff", plot = age_IFRraw_plot_ch, width = 7, height = 5)


#......................
# standardized deaths by age
#......................
age_std_cum_deaths_plot <- ageplotdat %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  dplyr::filter(seromidpt == obsday) %>%
  dplyr::select(c("study_id", "age_mid", "std_cum_deaths", "popn", "seroprevadj")) %>%
  dplyr::mutate(seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_line(aes(x = age_mid, y = std_cum_deaths, color = study_id), alpha = 0.8, size = 1.2) +
  geom_point(aes(x = age_mid, y = std_cum_deaths, fill = seroprevadj), color = "#000000", size = 2.5, shape = 21, alpha = 0.8) +
  scale_color_manual("Study ID", values = mycolors) +
  scale_fill_gradientn("Adj. Seroprevalence (%)",
                       colors = c(wesanderson::wes_palette("Zissou1", 100, type = "continuous"))) +
  xlab("Age (yrs).") + ylab("Cum. Deaths per Million") +
  labs(caption = "Cumulative Deaths per Million at midpoint of Seroprevalence Study") +
  xyaxis_plot_theme
if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/age_std_cum_deaths_plot.jpg",
                           plot = age_std_cum_deaths_plot)


#......................
# cumulative proportion deaths by age
#......................
age_IFRraw_plot0 <- age_IFRraw_plot0 %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  dplyr::mutate(d_per_mill=cumdeaths/popn)

tot_deaths <- age_IFRraw_plot0 %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  dplyr::group_by(study_id) %>%
  dplyr::summarise(tot_deaths=sum(cumdeaths),
                   tot_deaths_std=sum(d_per_mill)) %>%
  dplyr::select(study_id, tot_deaths,tot_deaths_std) %>%
  ungroup()

age_prop_deaths_plotdat <- full_join(age_IFRraw_plot0,tot_deaths,by="study_id") %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  dplyr::mutate(prop_deaths = cumdeaths/tot_deaths,
                prop_deaths_std = d_per_mill/tot_deaths_std) %>%
  dplyr::arrange(study_id,age_mid)

cumu_deaths <- age_prop_deaths_plotdat %>%
  dplyr::group_by(study_id,age_mid) %>%
  dplyr::summarise(cum_prop_deaths=cumsum(prop_deaths),
                   cum_prop_deaths_std=cumsum(prop_deaths_std))

age_prop_deaths_plotdat <-age_prop_deaths_plotdat %>%
  dplyr::mutate(cum_prop_deaths=cumu_deaths$cum_prop_deaths,
                cum_prop_deaths_std=cumu_deaths$cum_prop_deaths_std,
                age_low = as.numeric(stringr::str_extract(ageband, "[0-9]+(?=\\,)")),
                age_high= as.numeric(stringr::str_extract(ageband, "[0-9]+?(?=])")))

prop_deaths_70<-age_prop_deaths_plotdat %>%
  dplyr::mutate(ageband2=ifelse(age_low<69,"0-69","70+")) %>%
  dplyr::group_by(study_id,ageband2) %>%
  dplyr::summarise(prop_deaths=sum(prop_deaths),
                   prop_deaths_std=sum(prop_deaths_std)) %>%
  dplyr::filter(ageband2=="70+")

########## Raw deaths by age cumulative (just showing us the population structure more than anything?)
age_prop_deaths_plot<-ggplot(age_prop_deaths_plotdat, aes(x = age_mid, y = cum_prop_deaths, group=study_id)) +
  #geom_point(aes(fill = study_id), color = "#000000", size = 2.5, shape = 21, alpha = 0.8) +
  geom_line(aes(color = study_id), alpha = 0.8, size = 1.2) +
  scale_color_manual("Study ID", values = mycolors) +
  xlab("Age (yrs)") + ylab("Cumulative proportion of deaths") +
  xyaxis_plot_theme
if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/age_prop_cum_deaths_plot.jpg",
                           plot = age_prop_deaths_plot)

########## Deaths per capita by age cumulative
age_prop_deaths_plot_std <- age_prop_deaths_plotdat %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  ggplot() + theme_bw() +
  geom_line(aes(x = age_mid, y = cum_prop_deaths_std, group=study_id,color=study_id), size = 0.3) +
  scale_color_manual(values = mycolors, name = "study_id") +
  xlab("Age (yrs)") + ylab("Cumulative proportion of deaths, age-standardised") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/age_prop_deaths_plot_std.tiff", plot = age_prop_deaths_plot_std, width = 7, height = 5)

#......................
# daily standardized deaths by age
#......................
age_std_daily_deaths_plot <- ageplotdat %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  dplyr::select(c("study_id", "obsday", "ageband", "age_mid", "std_deaths", "popn", "seroprevadj")) %>%
  dplyr::mutate(ageband = forcats::fct_reorder(ageband, age_mid),
                seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_line(aes(x = obsday, y = std_deaths, color = ageband), alpha = 0.8, size = 1.2) +
  facet_wrap(.~study_id, scales = "free_y") +
  xlab("Obs. Day") + ylab("Daily Deaths per Million") +
  xyaxis_plot_theme
if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/age_std_daily_deaths_plot.jpg",
                           plot = age_std_daily_deaths_plot)

#............................................................
#----  Regional Plots/Descriptions #----
#...........................................................
rgnplotdat <- datmap %>%
  dplyr::filter(breakdown == "region" & care_home_deaths=="yes") %>%
  dplyr::select(c("study_id", "plotdat")) %>%
  tidyr::unnest(cols = "plotdat")

# filter to only plot the latest serology when there are multiple rounds
maxDays <- rgnplotdat %>%
  dplyr::group_by(study_id) %>%
  dplyr::summarise(max_day=max(obsdaymax))
rgnplotdat <- dplyr::full_join(rgnplotdat,maxDays,by="study_id")
rgnplotdat <- dplyr::filter(rgnplotdat,obsdaymax==max_day)

#......................
# rgn adj seroprevalence
#......................
# col_vec<-study_cols$study_cols
# names(col_vec) <- study_cols$study_id
rgn_seroplot <- rgnplotdat %>%
  dplyr::select(c("study_id", "region", "seroprev")) %>%
  dplyr::mutate(seroprev = seroprev * 100) %>%
  ggplot() + theme_bw() +
  geom_point(aes(x = region, y = seroprev, color = study_id), size = 2.5) +
  scale_color_manual(values = mycolors, name = "study_id") +
  facet_wrap(.~study_id, scales = "free_x") +
  xlab("Region") + ylab("Raw Seroprevalence (%)") +
  xyaxis_plot_theme +
  theme(axis.text.x = element_text(family = "Helvetica", hjust = 1, size = 8, angle = 45))

if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/rgn_raw_seroplot.jpg",
                           plot = rgn_seroplot)
########## Deaths per capita by age cumulative
age_prop_deaths_plot_std <- age_prop_deaths_plotdat %>%
  dplyr::filter(care_home_deaths=="yes") %>%
  ggplot() + theme_bw() +
  geom_line(aes(x = age_mid, y = cum_prop_deaths_std, group=study_id,color=study_id), size = 0.3) +
  scale_color_manual(values = mycolors, name = "study_id") +
  xlab("Age (yrs)") + ylab("Cumulative proportion of deaths, age-standardised") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/age_prop_deaths_plot_std.tiff", plot = age_prop_deaths_plot_std, width = 7, height = 5)




#......................
# rgn adj seroprevalence
#......................
rgn_seroplot <- rgnplotdat %>%
  dplyr::select(c("study_id", "region", "seroprevadj")) %>%
  dplyr::mutate(seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_point(aes(x = region, y = seroprevadj, color = study_id), size = 2.5) +
  scale_color_manual("Study ID", values = mycolors) +
  facet_wrap(.~study_id, scales = "free_x") +
  xlab("Region") + ylab("Adj. Seroprevalence (%)") +
  xyaxis_plot_theme +
  theme(axis.text.x = element_text(family = "Helvetica", hjust = 1, size = 8, angle = 45))

if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/rgn_adj_seroplot.jpg",
                           plot = rgn_seroplot)
#......................
# crude raw IFR
#......................
rgn_IFR_plot <- rgnplotdat %>%
  dplyr::filter(seromidpt == obsday) %>%
  dplyr::select(c("study_id", "region", "cumdeaths", "popn", "seroprev")) %>%
  dplyr::mutate(infxns = popn * seroprev,
                crudeIFR =  cumdeaths/(infxns+cumdeaths),
                crudeIFR = ifelse(crudeIFR > 1, 1, crudeIFR),
                seroprev = seroprev * 100 ) %>%
  dplyr::filter(infxns > 0) %>%
  ggplot() +
  geom_point(aes(x = region, y = crudeIFR, color = seroprev), size = 2.5) +
  facet_wrap(.~study_id, scales = "free_x") +
  scale_color_gradientn("Raw Seroprevalence (%)",
                        colors = c(wesanderson::wes_palette("Zissou1", 100, type = "continuous"))) +
  xlab("Region") + ylab("Crude Infection Fatality Rate") +
  xyaxis_plot_theme +
  theme(axis.text.x = element_text(family = "Helvetica", hjust = 1, size = 8, angle = 45))

if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/rgn_IFR_raw_plot.jpg",
                           plot = rgn_IFR_plot)

#......................
# crude adj IFR
#......................
rgn_IFR_plot <- rgnplotdat %>%
  dplyr::filter(seromidpt == obsday) %>%
  dplyr::select(c("study_id", "region", "cumdeaths", "popn", "seroprevadj")) %>%
  dplyr::mutate(infxns = popn * seroprevadj,
                crudeIFR =  cumdeaths/(infxns+cumdeaths),
                crudeIFR = ifelse(crudeIFR > 1, 1, crudeIFR),
                seroprevadj = seroprevadj * 100 ) %>%
  dplyr::filter(infxns > 0) %>%
  ggplot() +
  geom_point(aes(x = region, y = crudeIFR, color = seroprevadj), size = 2.5) +
  facet_wrap(.~study_id, scales = "free_x") +
  scale_color_gradientn("Adj. Seroprevalence (%)",
                        colors = c(wesanderson::wes_palette("Zissou1", 100, type = "continuous"))) +
  xlab("Region") + ylab("Crude Infection Fatality Rate") +
  xyaxis_plot_theme +
  theme(axis.text.x = element_text(family = "Helvetica", hjust = 1, size = 8, angle = 45))

if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/rgn_IFR_adj_plot.jpg",
                           plot = rgn_IFR_plot)

#......................
# standardized deaths by seroprev
#......................
std_deaths_seroplotdat <- rgnplotdat %>%
  dplyr::filter(seromidpt == obsday & study_id!="BRA1")
## add brazil city data
braz_temp<-std_deaths_seroplotdat[1:nrow(braz_dat_reg),]
for(i in 1:ncol(braz_temp)) braz_temp[,i]<-rep(NA,nrow(braz_dat_reg))
braz_temp$study_id<-"BRA1"
braz_temp$region<- braz_dat_reg$city
braz_temp$cumdeaths<-braz_dat_reg$deaths
braz_temp$seroprev<-braz_dat_reg$seroprevalence
braz_temp$popn<-braz_dat_reg$population
braz_temp$std_cum_deaths<-1000000*braz_temp$cumdeaths/braz_temp$popn
std_deaths_seroplotdat<-rbind(std_deaths_seroplotdat,braz_temp)
std_deaths_seroplotdat<-left_join(std_deaths_seroplotdat,study_cols,by="study_id")

# write out for later use
write.csv(std_deaths_seroplotdat, file = "data/derived/region_summ_IFR.csv")

# Death rate vs seroprevalence
std_deaths_seroplot <- std_deaths_seroplotdat %>%
  dplyr::select(c("study_id", "region", "std_cum_deaths", "popn", "seroprev")) %>%
  dplyr::mutate(seroprev = seroprev * 100) %>%
  ggplot() + theme_bw() +
  geom_point(aes(x = seroprev, y = std_cum_deaths, fill = study_id), shape = 21, size = 2.5, stroke = 0.2) +
  scale_fill_manual(values = mycolors, name = "Study") +
  xlab("Seroprevalence (%)") + ylab("Cumulative Deaths per Million") +
  #  labs(caption = "Cumulative deaths per million at midpoint of seroprevalence study") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/std_deaths_rgn_seroplot.tiff", plot = std_deaths_seroplot, width = 7, height = 5)

std_rgn_ifr_seroplot <- std_deaths_seroplotdat %>%
  dplyr::select(c("study_id", "region", "std_cum_deaths", "popn", "seroprev")) %>%
  dplyr::mutate(seroprev = seroprev * 100) %>%
  ggplot() + theme_bw() +
  geom_point(aes(x = seroprev, y = std_cum_deaths/(10000*seroprev), fill = study_id), shape = 21, size = 2.5, stroke = 0.2) +
  scale_fill_manual(values = mycolors, name = "study_id") +
  xlab("Seroprevalence (%)") + ylab("IFR (%)") +
  xyaxis_plot_theme
if(write2file) ggsave(filename = "results/descriptive_figures/std_rgn_ifr_seroplot.tiff", plot = std_rgn_ifr_seroplot, width = 7, height = 5)

# standardized deaths with names of regions (busy plot for internal)
std_deaths_seroplot_busy <- std_deaths_seroplotdat %>%
  dplyr::select(c("study_id", "region", "std_cum_deaths", "popn", "seroprevadj")) %>%
  dplyr::mutate(seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_point(aes(x = seroprevadj, y = std_cum_deaths, color = study_id), size = 2) +
  ggrepel::geom_text_repel(aes(x = seroprevadj, y = std_cum_deaths, label = region)) +
  scale_color_manual("Study ID", values = mycolors) +
  xlab("Adjusted Seroprevalence (%).") + ylab("Cumulative Deaths per Million") +
  xyaxis_plot_theme
if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/std_deaths_rgn_seroplot_busy.jpg",
                           plot = std_deaths_seroplot_busy, width_wide = 8, height_wide = 5.5)



std_deaths_seroplot <- rgnplotdat %>%
  dplyr::filter(seromidpt == obsday) %>%
  dplyr::select(c("study_id", "region", "std_cum_deaths", "popn", "seroprevadj")) %>%
  dplyr::mutate(seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_point(aes(x = seroprevadj, y = std_cum_deaths, color = study_id), size = 1.2) +
  ggrepel::geom_text_repel(aes(x = seroprevadj, y = std_cum_deaths, label = region), size = 2.5) +
  facet_wrap(.~study_id) +
  scale_color_manual("Study ID", values = mycolors) +
  xlab("Adj. Seroprevalence (%).") + ylab("Cum. Deaths per Million") +
  labs(caption = "Cumulative Deaths per Million at midpoint of Seroprevalence Study") +
  xyaxis_plot_theme
if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/std_deaths_seroplot_labeled.jpg",
                           plot = std_deaths_seroplot)


#......................
# standardized deaths by rgn
#......................
rgn_std_cum_deaths_plot <- rgnplotdat %>%
  dplyr::filter(seromidpt == obsday) %>%
  dplyr::select(c("study_id", "region", "std_cum_deaths", "popn", "seroprevadj")) %>%
  dplyr::mutate(seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_point(aes(x = region, y = std_cum_deaths, fill = seroprevadj), color = "#000000", size = 2.5, shape = 21, alpha = 0.8) +
  facet_wrap(.~study_id, scales = "free_x") +
  scale_color_manual("Study ID", values = mycolors) +
  scale_fill_gradientn("Adj. Seroprevalence (%)",
                       colors = c(wesanderson::wes_palette("Zissou1", 100, type = "continuous"))) +
  xlab("Region") + ylab("Cum. Deaths per Million") +
  labs(caption = "Cumulative Deaths per Million at midpoint of Seroprevalence Study") +
  xyaxis_plot_theme +
  theme(axis.text.x = element_text(family = "Helvetica", hjust = 1, size = 8, angle = 45))

if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/rgn_std_cum_deaths_plot.jpg",
                           plot = rgn_std_cum_deaths_plot)
#......................
# daily standardized deaths by rgn
#......................
rgn_std_daily_deaths_plot <- rgnplotdat %>%
  dplyr::select(c("study_id", "obsday", "region", "region", "std_deaths", "popn", "seroprevadj")) %>%
  dplyr::mutate(seroprevadj = seroprevadj * 100) %>%
  ggplot() +
  geom_line(aes(x = obsday, y = std_deaths, color = region), alpha = 0.8, size = 1.2) +
  facet_wrap(.~study_id) +
  xlab("Obs. Day") + ylab("Daily Deaths per Million") +
  xyaxis_plot_theme +
  theme(legend.position = "none")
if(write2file) jpgsnapshot(outpath = "figures/descriptive_figures/rgn_std_daily_deaths_plot.jpg",
                           plot = rgn_std_daily_deaths_plot)

#......................
# population structure
#......................
populationdf <- readr::read_tsv("data/raw/non_usa_non_bra_population.tsv") %>%
  dplyr::select(-c("reference")) %>%
  dplyr::filter(age_breakdown==1 & !is.na(study_id) & study_id!="IRN1" & study_id!="KEN1") %>%
  dplyr::arrange(study_id,age_low,age_high) %>%
  dplyr::group_by(study_id,age_high) %>%
  dplyr::summarise(pop=sum(population)) %>%
  dplyr::ungroup()

pop_tot<-populationdf %>%
  dplyr::group_by(study_id) %>%
  dplyr::summarise(tot_pop=sum(pop)) %>%
  dplyr::select(study_id,tot_pop) %>%
  dplyr::ungroup()

populationdf <- full_join(populationdf,pop_tot,by="study_id") %>%
  dplyr::mutate(prop_pop=pop/tot_pop,
                age_high=replace(age_high,age_high==999,100))

cumu <- populationdf %>%
  dplyr::group_by(study_id) %>%
  dplyr::arrange(study_id,age_high) %>%
  dplyr::summarise(cum_prop_pop=cumsum(prop_pop))
populationdf$cum_prop_pop<-cumu$cum_prop_pop

pop_age_plot <-ggplot(populationdf, aes(x = age_high, y = cum_prop_pop,group=study_id)) +
  geom_line(aes(color = study_id), alpha = 0.8, size = 1) +
  xlab("Age") + ylab("Cumulative proportion of population") +
  coord_cartesian(xlim = c(50,100), ylim=c(0.5,1))  +
  xyaxis_plot_theme #+
if(write2file) jpgsnapshot(outpath = "results/descriptive_figures/pop_cum_age_plot.jpg",
                           plot = pop_age_plot,width_wide = 8,height_wide = 5.5)

over80<-populationdf %>%
  dplyr::mutate(ageband=cut(age_high,breaks=c(-1,81,1000))) %>%
  dplyr::group_by(study_id,ageband) %>%
  dplyr::summarise(prop_pop=sum(prop_pop)) %>%
  dplyr::filter(ageband=="(81,1e+03]")

###### OVERALL IFRS
age_IFRraw_plot0<-read.csv("data/derived/age_summ_IFR.csv")
ifr0<-age_IFRraw_plot0 %>%
  dplyr::group_by(study_id) %>%
  dplyr::summarise(n_deaths=sum(cumdeaths),
                   infxns=sum(infxns),
                   pop=sum(popn)) %>%
  dplyr::mutate(ifr=n_deaths/(infxns+n_deaths))
ifr0<-full_join(ifr0,over80,by="study_id")
ifr0$prop_pop[which(ifr0$study_id=="GBR3")]<-0.04454408
ifr0$prop_pop[which(ifr0$study_id=="BRA1")]<-0.021
ifr0<-full_join(ifr0,prop_deaths_70,by="study_id")


par(mfrow=c(1,1))
plot(ifr0$prop_pop,ifr0$ifr*100,ylab="IFR (%)",xlab="proportion of population over 80",pch=19)


#............................................................
#---- Figure of Seroprevalence By Age #----
#...........................................................
dir.create("figures/final_figures/", recursive = TRUE)
datmap <- readRDS("results/descriptive_results/descriptive_results_datamap.RDS")
# colors now based on location
locatkey <- readr::read_csv("data/plot_aesthetics/color_studyid_map.csv")
mycolors <- locatkey$cols
names(mycolors) <- locatkey$location
locatkey <- locatkey %>%
  dplyr::select(c("location", "study_id")) %>%
  dplyr::filter(!grepl("_nch", study_id))

# SeroPrevalences by age portion
SeroPrevPlotDat <- datmap %>%
  dplyr::filter(breakdown == "ageband") %>%
  dplyr::filter(!grepl("_nch", study_id)) %>%
  dplyr::select(c("study_id", "seroprev_adjdat")) %>%
  dplyr::filter(! study_id %in% c(c("CHE2", "DNK1", "SWE1"))) %>% # excluding studies w/ constant assumption
  tidyr::unnest(cols = "seroprev_adjdat")

# filter to latest date if multiple serosurveys
SeroPrevPlotDat <- SeroPrevPlotDat %>%
  dplyr::filter(!c(study_id == "NLD1" & obsdaymin == 131)) %>% # manually handle NLD1 which has constant for timepoint 2 but not for timepoint 1
  dplyr::group_by(study_id, ageband) %>%
  dplyr::filter(obsdaymax == max(obsdaymax))

# add uncertainty in raw seroprevalence based on binomial
SeroPrevPlotDat_sub <- SeroPrevPlotDat %>%
  dplyr::filter(!is.na(n_positive)) %>%
  dplyr::filter(!is.na(n_tested)) %>%
  dplyr::mutate(crude_seroprev_obj = purrr::map2(n_positive, n_tested, .f = function(x,n){ binom.test(x,n) }),
                crude_seroprev_CI = purrr::map(crude_seroprev_obj, "conf.int"),
                crude_seroprevLCI = purrr::map_dbl(crude_seroprev_CI, function(x){x[[1]]}),
                crude_seroprevUCI = purrr::map_dbl(crude_seroprev_CI, function(x){x[[2]]}),
                crude_seroprev = purrr::map_dbl(crude_seroprev_obj, "estimate"))
# add back in ITA, which only have 95% CIs
SeroPrevPlotDat <- SeroPrevPlotDat %>%
  dplyr::filter(study_id == "ITA1") %>%
  dplyr::mutate(crude_seroprev_obj = NA,
                crude_seroprev_CI = NA,
                crude_seroprevLCI = serolci,
                crude_seroprevUCI = serouci,
                crude_seroprev = seroprev) %>%
  dplyr::bind_rows(., SeroPrevPlotDat_sub)


# plot out
SeroPrevPlotObj <- SeroPrevPlotDat %>%
  dplyr::left_join(., locatkey, by = "study_id") %>%
  dplyr::mutate(age_mid = purrr::map_dbl(ageband, get_mid_age),
                crude_seroprev = round(crude_seroprev * 100, 2),
                crude_seroprevLCI = round(crude_seroprevLCI * 100, 2),
                crude_seroprevUCI = round(crude_seroprevUCI * 100, 2)) %>%
  ggplot() +
  geom_pointrange(aes(x = age_mid, y = crude_seroprev, ymin = crude_seroprevLCI, ymax = crude_seroprevUCI,
                      color = location), alpha = 0.8) +
  geom_line(aes(x = age_mid, y = crude_seroprev, color = location),
            alpha = 0.8, size = 1.2, show.legend = F) +
  scale_color_manual("Location", values = mycolors) +
  xlab("Age (yrs).") + ylab("Observed Seroprevalence (%)") +
  xyaxis_plot_theme +
  theme(legend.position = "bottom")

jpeg("figures/final_figures/Figure_age_seroprev.jpg",
     width = 8, height = 6, units = "in", res = 500)
plot(SeroPrevPlotObj)
graphics.off()



#............................................................
#---- Figure of Obs Seroprevalence vs. Cum Deaths and Not-Modelled Adj. IFR #----
#...........................................................
set.seed(48)
source("R/monte_carlo_cis.R")
# get regions
rgns <- datmap %>%
  dplyr::filter(breakdown == "region") %>%
  dplyr::select(-c("care_home_deaths", "data", "seroprev_adjdat", "std_deaths")) %>%
  tidyr::unnest(cols = "plotdat")


# drop BRA states in favor of cities
rgns <- rgns %>%
  dplyr::filter(study_id != "BRA1")

#......................
# bra cities
#......................
# bra sero
bracities_sero <- readr::read_csv("data/raw/bra1_city_sero.csv") %>%
  dplyr::rename(n_tested = Tests,
                region = City) %>%
  dplyr::filter(!is.na(seroprevalence)) %>%
  dplyr::mutate(study_id = "BRA1",
                location = "Brazil",
                n_positive = round(seroprevalence * n_tested),
                seroprev = n_positive/n_tested) %>%
  dplyr::select(c("study_id", "location", "region", "n_tested", "n_positive", "seroprev"))

# add in popN
bracities_popn <- readr::read_csv("data/raw/bra1_city_pops.csv") %>%
  dplyr::select(-c("region")) %>%
  dplyr::rename(region = city) %>%
  dplyr::group_by(region) %>%
  dplyr::summarise(popn = sum(population))

# add in death
bracities_deaths <- readr::read_csv("data/raw/bra1_city_deaths.csv") %>%
  dplyr::select(-c("region")) %>%
  dplyr::rename(region = city) %>%
  dplyr::left_join(., bracities_popn) %>%
  dplyr::mutate(cumdeaths = (deaths_100k / 1e5) * popn)


# bring together brazil
brargn <- dplyr::left_join(bracities_sero, bracities_deaths) %>%
  dplyr::select(-c("cases_100k", "deaths_100k", "ifr")) %>%
  dplyr::mutate(seromidpt = 1, # just a place holder
                obsday = 1, # just a place holder
                std_cum_deaths = (cumdeaths/popn) * 1e6) %>%
  dplyr::filter(seroprev > 0)


#......................
# new regions
#......................
rgns <- dplyr::bind_rows(rgns, brargn)

#......................
# calculate CIs for binomial
#......................
rgns_binom <- rgns %>%
  dplyr::filter(study_id != "ITA1") %>%
  dplyr::group_by(study_id) %>%
  dplyr::filter(seromidpt == max(seromidpt)) %>% # latest serostudy
  dplyr::filter(obsday == seromidpt) %>% # latest serostudy
  dplyr::ungroup(.) %>%
  dplyr::select(c("study_id", "region", "cumdeaths", "popn", "n_positive", "n_tested", "std_cum_deaths")) %>%
  dplyr::filter(!duplicated(.)) %>%
  dplyr::group_by(study_id, region) %>%
  dplyr::mutate(seroprev = n_positive/n_tested,
                ifr_range = purrr::map(cumdeaths, get_binomial_monte_carlo_cis, popN = popn,
                                       npos = n_positive, ntest = n_tested, iters = 1e5),
                crudeIFR = cumdeaths/((seroprev * popn) + cumdeaths),
                lower_ci = purrr::map_dbl(ifr_range, quantile, 0.025),
                upper_ci = purrr::map_dbl(ifr_range, quantile, 0.975)) %>%
  dplyr::select(c("study_id", "region", "seroprev", "crudeIFR", "lower_ci", "upper_ci", "std_cum_deaths")) %>%
  dplyr::ungroup(.)

#......................
# calculate CIs for logit
#......................
rgns_logit <- rgns %>%
  dplyr::filter(study_id == "ITA1") %>%
  dplyr::filter(seromidpt == max(seromidpt)) %>% # latest serostudy
  dplyr::filter(obsday == seromidpt) %>% # latest serostudy
  dplyr::select(c("study_id", "region", "cumdeaths", "popn", "seroprev",  "serolci", "serouci", "std_cum_deaths")) %>%
  dplyr::filter(!duplicated(.)) %>%
  dplyr::group_by(study_id, region) %>%
  dplyr::mutate(SE = (COVIDCurve:::logit(serouci) - COVIDCurve:::logit(serolci))/(1.96 * 2))  %>%
  dplyr::mutate(ifr_range = purrr::map(cumdeaths, get_normal_monte_carlo_cis, popN = popn,
                                       mu = seroprev, sigma = SE, iters = 1e5),
                crudeIFR = cumdeaths/((seroprev * popn) + cumdeaths),
                lower_ci = purrr::map_dbl(ifr_range, quantile, 0.025),
                upper_ci = purrr::map_dbl(ifr_range, quantile, 0.975)) %>%
  dplyr::select(c("study_id", "region", "seroprev", "crudeIFR", "lower_ci", "upper_ci", "std_cum_deaths")) %>%
  dplyr::ungroup(.)

rgns_crudeIFRs_CI <- dplyr::bind_rows(rgns_binom, rgns_logit)



#......................
# make plots
#......................
upperbounds <- rgns_crudeIFRs_CI %>%
  dplyr::left_join(., locatkey, by = "study_id") %>%
  dplyr::filter(upper_ci > 0.05) %>%
  dplyr::mutate(seroprev = seroprev * 100,
                upbound = 5) # we multiple by 100 below


PanelA <- rgns_crudeIFRs_CI %>%
  dplyr::left_join(., locatkey, by = "study_id") %>%
  dplyr::mutate(seroprev = seroprev * 100) %>%
  ggplot() +
  geom_point(aes(x = seroprev, y = std_cum_deaths, color = location),
             size = 3, alpha = 0.7) +
  scale_color_manual("Location", values = mycolors) +
  xlab("Observed Seroprevalence (%)") + ylab("Cum. Deaths Per Million") +
  xyaxis_plot_theme +
  theme(legend.position = "bottom")  +
  theme(plot.margin = unit(c(0.05, 0.05, 0.5, 1),"cm"))


PanelB <- rgns_crudeIFRs_CI %>%
  dplyr::left_join(., locatkey, by = "study_id") %>%
  dplyr::mutate(seroprev = seroprev * 100,
                upper_ci = ifelse(upper_ci > 0.05, 0.05, upper_ci),
                crudeIFR = crudeIFR * 100,
                lower_ci = lower_ci * 100,
                upper_ci = upper_ci * 100) %>%
  ggplot() +
  geom_pointrange(aes(x = seroprev, y = crudeIFR,
                      ymin = lower_ci, ymax = upper_ci,
                      color = location), alpha = 0.8) +
  geom_point(data = upperbounds, aes(x = seroprev, y = upbound, color = location),
             shape = 3, size = 1.5, alpha = 0.8) +
  scale_color_manual("Study ID", values = mycolors) +
  xlab("Observed Seroprevalence (%)") + ylab("Crude IFR (95% CI)") +
  xyaxis_plot_theme +
  theme(legend.position = "bottom") +
  theme(plot.margin = unit(c(0.05, 0.05, 0.5, 1),"cm"))



# bring together
PanelA_nolegend <- PanelA + theme(legend.position = "none")
PanelB_nolegend <- PanelB + theme(legend.position = "none")
legend <- cowplot::get_legend(PanelA)
mainfig <- cowplot::plot_grid(PanelA_nolegend, PanelB_nolegend,
                              labels = c("(A)", "(B)", nrow = 1))
(mainfig <- cowplot::plot_grid(mainfig, legend, ncol = 1, rel_heights = c(1, 0.1)))


jpeg("figures/final_figures/Figure_Rgn_crude_IFR.jpg",
     width = 11, height = 8, units = "in", res = 500)
plot(mainfig)
graphics.off()




# #............................................................
# #---- Figure of Regional Serofit Summaries #----
# #...........................................................
# library(rstan)
# # Death rate vs seroprevalence
# std_deaths_seroplotdat<-read.csv("results/Rgn_Mod_Rets/region_summ_IFR.csv")
# col_vec<-study_cols$cols
# names(col_vec) <- study_cols$names
# std_deaths_seroplot <- std_deaths_seroplotdat %>%
#   dplyr::select(c("names", "region", "std_cum_deaths", "popn", "seroprev")) %>%
#   dplyr::mutate(seroprev = seroprev * 100) %>%
#   ggplot() + theme_bw() +
#   geom_point(aes(x = seroprev, y = std_cum_deaths, fill = names), shape = 21, size = 2.5, stroke = 0.2) +
#   scale_fill_manual(values = mycolors, name = "Study ID") +
#   xlab("Seroprevalence (%)") + ylab("Cumulative Deaths per Million") +
#   #  labs(caption = "Cumulative deaths per million at midpoint of seroprevalence study") +
#   xyaxis_plot_theme
#
#
# spainFit<-readRDS("results/Rgn_Mod_Rets/fit_spain_reg_age_full_new.rds")
# params<-extract(spainFit)
# spainDat<-std_deaths_seroplotdat %>%
#   filter(study_id=="ESP1-2")
# stanFit<-ggplot() + theme_bw() +
#   geom_point(aes(x = 100*spainDat$seroprev, y = spainDat$std_cum_deaths,color="Spain data"), shape = 19, size = 1.5,stroke=1.5) +
#   geom_point(aes(x = 100*colMeans(params$prev_sero_truer), y = 1000000*colMeans(params$expdr)/spainDat$popn,
#                  color="fitted"),
#              shape = 19, size = 2.5) +
#   expand_limits(x = 0) +
#   expand_limits(y = 1700) +
#   scale_color_manual(name="",values=c("Spain data"="black","fitted"="dodgerblue"), labels=c("fitted","Spain data")) +
#   xlab("Seroprevalence (%)") + ylab("Cumulative Deaths per Million") +
#   xyaxis_plot_theme
#
#
#
# rgnPlots <- cowplot::plot_grid(std_deaths_seroplot, stanFit,
#                                ncol = 2, nrow = 1, align = "h",
#                                labels = c("(A)", "(B)"), rel_widths = c(1.2,1))
# if(write2file) ggsave(filename = "results/descriptive_figures/rgnPlots.tiff", plot = rgnPlots, width = 13, height = 5)
