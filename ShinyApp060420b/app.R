library(rsconnect)
library(shiny)
library(dplyr)
#library(DT)
library(ggplot2)
library(tidyr)

#setwd("C:/Users/KristinBietsch/files/Track20/Win Requests/Self Injections/ShinyApp060420")

# Read in data
baseline <- read.csv("data/BaselineData052920.csv")
default <- read.csv("data/DefaultData061120.csv")
default <- default%>% select(-Country)
# combine
baseline <- full_join(baseline, default, by="iso")





# Define UI for app that draws a histogram ----
ui <- fluidPage(
  titlePanel(h1("Potential Market of Subcutaneous and Self-Injectable Contraceptive Users in FP2020 Countries through 2030")),
  
  sidebarLayout(
    sidebarPanel(img(src = "logo_150_trans1.png"),
                 h3("Choose Country") ,
                  selectInput("var", 
                              label = "Choose a Country",
                              choices = unique(baseline$Country),
                              selected = ""),
                  h3("Choose Parameters") ,
                  fluidRow( column(10, 
                                   numericInput("inj_to_si", 
                                                h5("Proportion of injectable users that will switch to subcutaneous injectable contraceptives"), 
                                                value=0.16, min = 0, max = 1, step = .01))   ),
                  fluidRow( column(10, 
                                   numericInput("stm_to_si", 
                                                h5("Proportion of short-term method users that will switch to subcutaneous injectable contraceptives"), 
                                                value=0.08, min = 0, max = 1, step = .01))   ),
                  fluidRow( column(10, 
                                   numericInput("nu_to_si", 
                                                h5("Proportion of non-users, whose reasons for not using would be alleviated by benefits of subcutaneous injection (decreased side-effects, increased availability, ease of use) that will uptake subcutaneous injectable contraceptives"), 
                                                value=0.04, min = 0, max = 1, step = .01))   ),
                  fluidRow( column(10, 
                                   numericInput("si_bonus", 
                                                h5("Increase in each of the above parameter when self-injection of subcutaneous becomes fully available (partial bonus awarded during scale up)"), 
                                                value=0.01, min = 0, max = 1, step = .01))   ),
                  fluidRow( column(10, 
                                   numericInput("max_siofsc", 
                                                h5("Maximum share of subcutaneous injectables that will be self-injected"), 
                                                value=0.4, min = 0, max = 1, step = .01))   )
    ),
    
    
    mainPanel(
      h2("Program Years"),
      fluidRow(
        column(5, 
               sliderInput("year_sc", h4("Year subcutaneous is at full-scale"),
                           min = 2019, max = 2030, value = 2020, sep="")),
        column(5, 
               sliderInput("year_si", h4("Year self-injection reaches maximum"),
                           min = 2019, max = 2030, value = 2024, sep=""))),
      h4("Note: Subcutaneous injectable must be at full scale before self-injection reaches maximum"),
      fluidRow(
        column(6, 
               plotOutput("plot1")),
        column(4, 
               plotOutput("plot2"))),
      dataTableOutput('table'),
      
      
      textOutput("Notes")
      
      
      
      
      
      
    )))



# Define server logic required to draw a histogram ----
server <- function(input, output, session) {
  
  
  vals <- reactiveValues()
  observe({
    
    vals$iso <- baseline$iso[baseline$Country==input$var]
  })
  
  
  

  
  dat<-reactive({
    
    Year <- c(seq(2019, 2030, 1))
    yearsdf <- as.data.frame(Year)
    
    yearsdf$SC <- input$year_sc
    yearsdf$SI <- input$year_si
    yearsdf$max_si <- input$max_siofsc
    yearsdf <- yearsdf %>% mutate(time_sc_si = SI - SC,
                                  years_after_sc=Year-SC,
                                  share_between_scsi = (years_after_sc/time_sc_si)*max_si,
                                  per_si =case_when(Year>=SI ~ max_si,
                                                    Year<=SC ~ 0,
                                                    Year>SC & Year<SI ~ share_between_scsi),
                                  share_bonus=per_si/max_si) %>% 
      select(Year, SC, SI, max_si, per_si, share_bonus) %>%
      mutate(id=1)
    
    
    
    si_firstsc <- baseline %>% filter(Year==2019) %>% select(iso, Injection, STM, NonUser, ReasonNotUsingSI, scale, high)  %>%
      mutate(id=1) %>% mutate(high_scale=case_when(high==1 ~ 1, high==0 ~ .9))
    si_firstsc <- full_join(si_firstsc, yearsdf, by="id") %>% select(-id)
    
    
    siannual <- si_firstsc %>% mutate(inj_switch_si_a=(((input$inj_to_si+(input$si_bonus*share_bonus))*scale*high_scale)*Injection)/11,
                                      stm_switch_si_a=(((input$stm_to_si+(input$si_bonus*share_bonus))*scale*high_scale)*STM)/11,
                                      nu_switch_si_a=(((input$nu_to_si+(input$si_bonus*share_bonus))*scale*high_scale)*NonUser*ReasonNotUsingSI)/11) %>%
      select(iso, Year, inj_switch_si_a, stm_switch_si_a, nu_switch_si_a, SC, SI, max_si)
    
    equations <- full_join(baseline, siannual, by=c("iso", "Year"))
    
    # Here is where the years since full scale matter- making annual numbers before it 0
    equations <- equations %>% mutate(year_fullscale= case_when(Year-SC<0 ~ 0, Year-SC>=0 ~ Year-SC+1 )) %>%
      mutate(binary_full_scale=case_when(year_fullscale>0 ~ 1, year_fullscale==0 ~ 0)) %>% 
      mutate(inj_switch_si_a=inj_switch_si_a*binary_full_scale,
             stm_switch_si_a=stm_switch_si_a*binary_full_scale,
             nu_switch_si_a=nu_switch_si_a*binary_full_scale) %>%
      group_by(iso) %>%
      mutate(inj_switch_si = cumsum(inj_switch_si_a),
             stm_switch_si = cumsum(stm_switch_si_a),
             inj_stay= Injection-inj_switch_si,
             stm_stay=STM-stm_switch_si) 
    
    #SI users who would have been non-users because of discontinuation from IM
    equations <- equations %>% mutate(si_non_disc_im = case_when(year_fullscale==0 ~ 0, year_fullscale!=0 ~ inj_switch_si*(discon_inj*.26)))
    
    # SI users who would have been non-users because of discontinuation from STM
    equations <- equations %>% mutate(si_non_disc_stm = case_when(year_fullscale==0 ~ 0, year_fullscale!=0 ~ stm_switch_si*(discon_stm*.26)))
    
    #Nonusers Not SI Relevant
    equations <- equations %>% mutate(nu_not_sirelevant=(NonUser-si_non_disc_im-si_non_disc_stm)*(1-ReasonNotUsingSI),
                                      nu_sirelevant=(NonUser-si_non_disc_im-si_non_disc_stm)*(ReasonNotUsingSI))
    
    
    equations <- equations %>% mutate( nu_sirelevant_uptake= cumsum(nu_switch_si_a))
    equations <- equations %>% mutate(nu_sirelevant_notuptake=nu_sirelevant-nu_sirelevant_uptake)
    
    names(equations)
    equations <- equations %>% mutate(si_users=inj_switch_si+stm_switch_si+si_non_disc_im+si_non_disc_stm+nu_sirelevant_uptake,
                                      im_users=inj_stay,
                                      stm_users=stm_stay,
                                      ltm_users=LTM,
                                      non_users=nu_not_sirelevant+nu_sirelevant_notuptake,
                                      per_users_si=si_users/(si_users+im_users+stm_users+ltm_users))
    
    
    
    # Proportion of SI Users from Various sources
    equations <- equations %>% mutate(prop_si_im= case_when(si_users==0 ~ 0, si_users!=0 ~ inj_switch_si/si_users),
                                      prop_si_stm= case_when(si_users==0 ~ 0, si_users!=0 ~ stm_switch_si/si_users),
                                      prop_si_disc= case_when(si_users==0 ~ 0, si_users!=0 ~ (si_non_disc_im+si_non_disc_stm)/si_users),
                                      prop_si_uptake= case_when(si_users==0 ~ 0, si_users!=0 ~ nu_sirelevant_uptake/si_users))
    
    # Users under different policies
    equations <- equations %>% mutate(baseline_users=LTM+STM+Injection,
                                      total_user_w_si=si_users+im_users+stm_users+ltm_users)
    
    # Injectable Users
    equations <- equations %>% mutate(injec_user_w_si=si_users+im_users)
    
    # IM Users, SI Users, and SC Users
    equations <- full_join(equations, yearsdf, by="Year")
    equations <- equations %>% mutate(IM_injec_user_w_si=round(im_users),
                                      SCP_injec_user_w_si=round(si_users*(1-per_si)),
                                      SI_injec_user_w_si= round(si_users*(per_si)),
                                      non_users <- Total-total_user_w_si,
                                      mcpr_w_si=round((total_user_w_si/Total)*100,1),
                                      baseline_mcpr=round((baseline_users/Total)*100,1))
    
    })
  
  
  datlong<-reactive({
    
    
    graph <-  dat() %>% select(iso, Year, IM_injec_user_w_si, SCP_injec_user_w_si, SI_injec_user_w_si, stm_users , ltm_users, non_users ) %>% 
      gather(Type, Number, IM_injec_user_w_si:non_users ) %>%
      mutate(Type=case_when(Type=="stm_users" ~ "STM",
                            Type=="ltm_users" ~ "LTM",
                            Type=="IM_injec_user_w_si" ~ "Injectable: IM",
                            Type=="SCP_injec_user_w_si" ~ "Injectable: SC (Provider)",
                            Type=="SI_injec_user_w_si" ~ "Injectable: SC (Self)",
                            Type=="non_users" ~ "Nonuser"))
    
    graph$Type <- factor(graph$Type, levels = c( "Injectable: SC (Self)", "Injectable: SC (Provider)", "Injectable: IM", "LTM", "STM", "Nonuser" ))
    
    
    graph <- graph %>% filter(iso==vals$iso)  
    
  })
  
  
  mcprdata<-reactive({
    
    mcpr <-  dat() %>% select(iso, Year, mcpr_w_si, baseline_mcpr ) %>%    gather(Type, Number, mcpr_w_si:baseline_mcpr )  %>%
      mutate(Type= case_when(Type=="mcpr_w_si" ~ "mCPR with SC Introduction",
             Type=="baseline_mcpr" ~ "mCPR without SC Introduction"))

    mcpr <- mcpr %>% filter(iso==vals$iso) 
    
    
  })
  
  
  
  output$table <- renderDataTable({
    
    
    table <- dat() %>% select(iso, Year,  SI_injec_user_w_si, SCP_injec_user_w_si, IM_injec_user_w_si, mcpr_w_si) 
    table <- table %>% filter(iso==vals$iso)
    table <- table %>% rename("Self-Injectable Users"=SI_injec_user_w_si, "Provider Injected SC Users"=SCP_injec_user_w_si, "Intramuscular Injectable Users"=IM_injec_user_w_si, "mCPR"=mcpr_w_si, ISO=iso)
  })
  
  output$plot1<-renderPlot({

    ggplot(datlong(),aes(x=Year,y=Number, fill=Type))+ 
      geom_bar(stat="identity") +
      labs(title="Number of Women", x="", y="", fill="")+
      theme_bw()+
      theme(legend.position = "bottom",
            legend.text=element_text(size=12))
    
    }, height = 400,width = 600)

  output$plot2<-renderPlot({
    
    ggplot(mcprdata(),aes(x=Year,y=Number, color=Type))+ 
      geom_line(size=1.5)+
      labs(title="Effect for Self-Injectable Introduction on mCPR", x="", y="mCPR (AW)", color="")+
      theme_bw()+
      theme(legend.position = "bottom",
            legend.text=element_text(size=12))
    
  }, height = 400,width = 400)
  
  
  output$Notes <- renderText({ 
    paste("Notes:", baseline$Country_note[baseline$Country==input$var & baseline$Year==2019])
    
  })
  
}


shinyApp(ui = ui, server = server)